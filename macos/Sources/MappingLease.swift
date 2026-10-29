import Foundation

/// Device-only mapping lease. It never changes global keyboard mappings.
/// Backups survive a crash and remain until restoration succeeds.
final class MappingLease {
    struct Mapping: Codable, Equatable { let source: UInt64; let destination: UInt64 }
    struct Lease: Codable { let matching: String; let owned: Set<UInt64>; let originals: [Mapping] }
    private let url: URL
    private var leases: [Lease] = []
    init(directory: URL) throws {
        url = directory.appendingPathComponent("key-mapping-leases.json")
        if FileManager.default.fileExists(atPath: url.path) {
            leases = try JSONDecoder().decode([Lease].self, from: Data(contentsOf: url))
        }
    }
    func apply(profile: DeviceProfile, groups: Set<RemoteInput.InterfaceGroup>, sources: Set<UInt64>, testMode:Bool = false) throws {
        try restore()
        if testMode && (sources.isEmpty || groups.isEmpty || sources.count>4096) {
            throw JustVibeRemoteError.message("The receiver’s button layout could not be isolated for testing.")
        }
        guard !sources.isEmpty else { return }
        do {
            for group in groups {
                let owned = testMode ? sources:Set(sources.filter { group.usage == 6 && group.page == 1 ? $0 >> 32 == 7 : $0 >> 32 != 7 })
                guard !owned.isEmpty else { continue }
                let matching = "{\"VendorID\":\(profile.vendorId),\"ProductID\":\(profile.productId),\"PrimaryUsagePage\":\(group.page),\"PrimaryUsage\":\(group.usage)}"
                let current = try read(matching)
                leases.append(Lease(matching: matching, owned: owned, originals: current.filter { owned.contains($0.source) }))
                try persist()
                let mappings = current.filter { !owned.contains($0.source) } + owned.sorted().map { Mapping(source: $0, destination: 0x0000_0007_0000_0000) }
                try write(matching, mappings)
                if testMode {
                    try Self.verifyTestMappings(try read(matching),sources:owned)
                }
            }
        } catch {
            try? restore()
            throw error
        }
    }
    static func verifyTestMappings(_ mappings:[Mapping],sources:Set<UInt64>) throws {
        guard !sources.isEmpty,sources.allSatisfy({ source in
            let entries=mappings.filter { $0.source == source }
            return entries.count == 1 && entries[0].destination == 0x0000_0007_0000_0000
        }) else { throw JustVibeRemoteError.message("macOS did not confirm that receiver button actions are blocked for testing.") }
    }
    func restore() throws {
        for index in leases.indices.reversed() {
            let lease = leases[index]
            do {
                let current = try read(lease.matching)
                try write(lease.matching, current.filter { !lease.owned.contains($0.source) } + lease.originals)
                leases.remove(at: index)
                try persist()
            } catch JustVibeRemoteError.deviceUnavailable {
                // Unplugged devices have no active system mapping to restore.
                // Keep the journal and restore it when they reconnect.
                continue
            }
        }
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(leases).write(to: url, options: .atomic)
    }
    private func read(_ matching: String) throws -> [Mapping] {
        let output = try run(["--matching", matching, "--get", "UserKeyMapping"])
        guard output.contains("UserKeyMapping") else { throw JustVibeRemoteError.deviceUnavailable }
        return try Self.parse(output)
    }
    static func parse(_ output: String) throws -> [Mapping] {
        guard output.components(separatedBy: "UserKeyMapping").count == 2 else {
            throw JustVibeRemoteError.message("Expected one receiver interface. Reconnect it, or disconnect other receivers with the same hardware ID, then try again.")
        }
        if output.contains("(null)") { return [] }
        let blocks = try NSRegularExpression(pattern: #"\{[^}]*\}"#)
        let fullRange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = blocks.matches(in: output, range: fullRange)
        if output.contains("HIDKeyboardModifierMappingSrc") && matches.isEmpty {
            throw JustVibeRemoteError.message("Cannot read existing device mappings safely; no changes were applied.")
        }
        func number(_ field: String, in text: String) throws -> UInt64 {
            let regex = try NSRegularExpression(pattern: field + #"\s*=\s*(\d+)\s*;"#)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let range = Range(match.range(at: 1), in: text), let value = UInt64(text[range]) else {
                throw JustVibeRemoteError.message("Invalid device mapping output; original mappings were preserved.")
            }
            return value
        }
        return try matches.map { match in
            guard let range = Range(match.range, in: output) else { throw JustVibeRemoteError.message("Invalid device mapping range.") }
            let text = String(output[range])
            return try Mapping(source: number("HIDKeyboardModifierMappingSrc", in: text), destination: number("HIDKeyboardModifierMappingDst", in: text))
        }
    }
    private func write(_ matching: String, _ values: [Mapping]) throws {
        let entries = values.map { ["HIDKeyboardModifierMappingSrc": $0.source, "HIDKeyboardModifierMappingDst": $0.destination] }
        let json = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": entries])
        let output = try run(["--matching", matching, "--set", String(decoding: json, as: UTF8.self)])
        guard output.contains("UserKeyMapping") else { throw JustVibeRemoteError.message("macOS did not confirm the device mapping change.") }
    }
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property"] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw JustVibeRemoteError.message("macOS rejected the device mapping request. Native input is preserved.") }
        return String(decoding: data, as: UTF8.self)
    }
}

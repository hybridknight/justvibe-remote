import Foundation

struct MicrophonePreference: Codable {
    var id: String
    var name: String
    var guardDictation: Bool
}
enum MicrophonePolicy {
    static func issue(_ preference: MicrophonePreference?, available: [String], defaults: [String]) -> String? {
        guard let preference, preference.guardDictation else { return nil }
        guard !preference.id.isEmpty, available.contains(preference.id) else { return "Selected remote microphone is disconnected. Open Microphone test; no shortcut was sent." }
        guard !defaults.isEmpty, defaults.allSatisfy({ $0 == preference.id }) else { return "System input is not the selected remote microphone. Open Microphone test; no shortcut was sent." }
        return nil
    }
}
/// A five-second mono PCM preview, held only in memory. No transcription or upload.
struct PCMPreview {
    let sampleRate: Int
    private(set) var samples: [Int16] = []
    private(set) var level: Double = 0
    var decibels: Double? { level > 0 ? 20 * log10(level) : nil }
    var meterPercent: Double { decibels.map { min(100,max(0,($0 + 72) / 72 * 100)) } ?? 0 }
    var hasSignal: Bool { samples.contains { $0 != 0 } }
    var capacity: Int { sampleRate * 5 }
    var full: Bool { samples.count >= capacity }
    mutating func append(_ incoming: [Int16]) {
        guard (8000...192000).contains(sampleRate) else { return }
        let accepted = incoming.prefix(max(0, capacity - samples.count))
        if !accepted.isEmpty { level = sqrt(accepted.reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / Double(accepted.count)) }
        samples.append(contentsOf: accepted)
    }
    func wave() -> Data {
        var data = Data()
        func tag(_ text: String) { data.append(contentsOf: text.utf8) }
        func u16(_ x: UInt16) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u32(_ x: UInt32) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        let size = UInt32(samples.count * 2)
        tag("RIFF"); u32(36 + size); tag("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16); tag("data"); u32(size)
        for sample in samples { u16(UInt16(bitPattern: sample)) }
        return data
    }
}

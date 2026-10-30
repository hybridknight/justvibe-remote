import Foundation

struct DeviceProfile: Codable, Equatable {
    var schemaVersion = 1
    var id: String
    var name: String
    var vendorId: Int
    var productId: Int
    var audio = "native-usb-microphone"
    var consumerReportId = 2
    var consumerReportLength = 3
    var consumerUsageOffset = 1
    var hardwareID: String { String(format: "%04X:%04X", vendorId, productId) }
    func validate() throws {
        guard schemaVersion == 1, (1...65535).contains(vendorId), (1...65535).contains(productId),
              ["native-usb-microphone", "none"].contains(audio), (1...255).contains(consumerReportId),
              (3...64).contains(consumerReportLength), consumerUsageOffset >= 1,
              consumerUsageOffset + 2 <= consumerReportLength else {
            throw JustVibeRemoteError.message("Invalid or unsupported device profile.")
        }
    }
    static let unselected = DeviceProfile(id: "unselected", name: "No device plugin selected", vendorId: 0, productId: 0)
}

struct Usage: Codable, Hashable {
    let page: UInt32
    let code: UInt32
    var label: String { String(format: "%04X:%04X", page, code) }
    var hidutilCode: UInt64 { UInt64(page) << 32 | UInt64(code) }
    var isButton: Bool {
        (page == 7 && (4..<0xE0).contains(code)) ||
        (page == 12 && code > 0) || (page == 1 && (0x81...0x83).contains(code))
    }
}

enum RemoteAction: String, Codable, CaseIterable {
    case native, dictate, focus, send, backspace, escape
    var title: String {
        switch self {
        case .native: return "Keep original action"
        case .dictate: return "Dictation"
        case .focus: return "Open app"
        case .send: return "Send (Return)"
        case .backspace: return "Delete previous character"
        case .escape: return "Escape"
        }
    }
}
struct Binding: Codable, Equatable {
    var name: String
    var usage: Usage?
    var action: RemoteAction
    var controlID: String?
    var launchAppID: String? = nil
    var launchAppPath: String? = nil
    static var initial: [Binding] {
        [Binding(name: "Microphone", action: .dictate),
         Binding(name: "Power", action: .native),
         Binding(name: "OK", usage: Usage(page: 7, code: 0x28), action: .native),
         Binding(name: "Back", usage: Usage(page: 12, code: 0x224), action: .native),
         Binding(name: "Home", usage: Usage(page: 12, code: 0x223), action: .native),
         Binding(name: "Menu", usage: Usage(page: 7, code: 0x65), action: .native)]
    }
}
/// Preferences shared by a remote's app profiles. Legacy settings remain the
/// current remote's snapshot until the first switch saves them here.
struct RemotePreferences: Codable, Equatable {
    var selectedAppID: String
    var followActiveApp: Bool
    var suppressOriginal: Bool
    var autoConnect: Bool
    var setupCompleted: Bool?
    var setupCheckpoint: RemoteSetupCheckpoint?
    init(_ config: Configuration) {
        selectedAppID = config.appPluginID
        followActiveApp = config.followActiveApp
        suppressOriginal = true
        autoConnect = config.autoConnect
        setupCompleted = config.remoteSetupCompleted;setupCheckpoint = config.remoteSetupCheckpoint
    }
}

enum SystemDictationMode:String,Codable,CaseIterable {
    case off, fallback, everywhere
    var title:String {
        switch self {
        case .off:return "Off"
        case .fallback:return "Use when app dictation is not configured"
        case .everywhere:return "Use in every app"
        }
    }
}
enum SystemDictationShortcut:String,Codable,CaseIterable {
    case microphone,controlTwice,globeTwice,rightCommandTwice,leftCommandTwice,eitherCommandTwice,custom
    var title:String {
        switch self {
        case .microphone:return "Press Microphone Key"
        case .controlTwice:return "Press Control Key Twice"
        case .globeTwice:return "Press Globe Key Twice"
        case .rightCommandTwice:return "Press Right Command Key Twice"
        case .leftCommandTwice:return "Press Left Command Key Twice"
        case .eitherCommandTwice:return "Press Either Command Key Twice"
        case .custom:return "Customize…"
        }
    }
}
struct SystemDictationSettings:Codable,Equatable {
    var mode:SystemDictationMode = .off
    var shortcut=""
    var confirmed=false
    var controlID="microphone"
    // Missing in older settings, which always used a custom chord.
    var preset:SystemDictationShortcut?
    var shortcutKind:SystemDictationShortcut { preset ?? .custom }
    var shortcutDescription:String { shortcutKind == .custom ? shortcut:shortcutKind.title }
    var enabled:Bool { mode != .off && confirmed && (shortcutKind != .custom || !shortcut.isEmpty) }
    func validate() throws {
        guard !controlID.isEmpty,controlID.count<=100 else { throw JustVibeRemoteError.message("Choose a remote button for dictation in any app.") }
        guard mode != .off else { return }
        guard confirmed else { throw JustVibeRemoteError.message("Confirm that the shortcut matches macOS Dictation in Keyboard settings.") }
        guard shortcutKind == .custom else { return }
        let chord=try MacShortcut.parse(shortcut)
        guard !chord.flags.isEmpty || MacShortcut.isFunctionKey(chord.key) else { throw JustVibeRemoteError.message("Use a modifier shortcut such as Control+Shift+D, or a function key such as F13.") }
    }
}

struct Configuration: Codable {
    static let noSpecificAppID = "justviberemote.no-specific-app"
    var schemaVersion = 1
    var remoteSetupCompleted = false
    var remoteSetupCheckpoint: RemoteSetupCheckpoint?
    var profile = DeviceProfile.unselected
    var devicePluginID = "org.justviberemote.device.xingwei-usb"
    var appPluginID = "org.justviberemote.app.chatgpt"
    var bindings = Binding.initial
    var voiceMode = "toggle"
    var shortcut = ""
    var shortcutConfirmed = false
    var targetAppPath = ""
    var bindingSets: [String: [Binding]] = [:]
    var remotePreferences: [String: RemotePreferences] = [:]
    var appMappings: [String: AppMapping] = [:]
    var followActiveApp = true
    var microphones: [String: MicrophonePreference] = [:]
    var cursorSettings: [String: CursorSpeedSettings] = [:]
    var systemDictation: [String:SystemDictationSettings] = [:]
    // Runtime routing only: never encode foreground identity or overwrite app settings.
    var usesSystemDictation=false
    var systemDictationTargetPID:Int32?
    var dictationTested = false
    var autoConnect = false
    // Kept in saved settings for compatibility; mapped-action replacement is mandatory.
    var suppressOriginal = true
    init() {}
    /// Hardware signals belong to a remote; each app retains its own action.
    mutating func linkButton(at index:Int,to usage:Usage) {
        guard bindings.indices.contains(index) else { return }
        let control=bindings[index]
        func linked(_ saved:[Binding]) -> [Binding] {
            let match=saved.firstIndex { binding in
                if let id=control.controlID,let savedID=binding.controlID { return id == savedID }
                return binding.name.caseInsensitiveCompare(control.name) == .orderedSame
            }
            return saved.enumerated().map { offset,binding in
                var next=binding
                if offset == match { next.usage=usage }
                else if next.usage == usage { next.usage=nil }
                return next
            }
        }
        // Update the chosen index even for legacy lists with duplicate names.
        for other in bindings.indices where other != index && bindings[other].usage == usage { bindings[other].usage=nil }
        bindings[index].usage=usage;dictationTested=false
        let prefix=devicePluginID + "|"
        for key in Array(bindingSets.keys) where key.hasPrefix(prefix) { bindingSets[key]=linked(bindingSets[key]!) }
        for key in Array(appMappings.keys) where key.hasPrefix(prefix) {
            var mapping=appMappings[key]!
            let updated=linked(mapping.bindings)
            if updated != mapping.bindings { mapping.bindings=updated;mapping.dictationTested=false }
            appMappings[key]=mapping
        }
    }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, remoteSetupCompleted, remoteSetupCheckpoint, profile, devicePluginID, appPluginID, bindings, voiceMode, shortcut, shortcutConfirmed, targetAppPath, suppressOriginal, bindingSets, remotePreferences, dictationTested, autoConnect, appMappings, followActiveApp, microphones, cursorSettings, systemDictation
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        profile = try values.decode(DeviceProfile.self, forKey: .profile)
        devicePluginID = try values.decodeIfPresent(String.self, forKey: .devicePluginID) ?? devicePluginID
        appPluginID = try values.decodeIfPresent(String.self, forKey: .appPluginID) ?? appPluginID
        bindings = try values.decode([Binding].self, forKey: .bindings)
        voiceMode = try values.decode(String.self, forKey: .voiceMode)
        shortcut = try values.decode(String.self, forKey: .shortcut)
        shortcutConfirmed = try values.decode(Bool.self, forKey: .shortcutConfirmed)
        targetAppPath = try values.decode(String.self, forKey: .targetAppPath)
        suppressOriginal = true
        dictationTested = try values.decodeIfPresent(Bool.self, forKey: .dictationTested) ?? false
        autoConnect = try values.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        remoteSetupCompleted = try values.decodeIfPresent(Bool.self, forKey: .remoteSetupCompleted)
            ?? (dictationTested || bindings.contains { $0.usage != nil && $0.action != .native && $0.action != .dictate })
        remoteSetupCheckpoint = try values.decodeIfPresent(RemoteSetupCheckpoint.self, forKey: .remoteSetupCheckpoint)
        appMappings = try values.decodeIfPresent([String: AppMapping].self, forKey: .appMappings) ?? [:]
        followActiveApp = try values.decodeIfPresent(Bool.self, forKey: .followActiveApp) ?? false
        cursorSettings = try values.decodeIfPresent([String: CursorSpeedSettings].self, forKey: .cursorSettings) ?? [:]
        systemDictation = try values.decodeIfPresent([String:SystemDictationSettings].self, forKey: .systemDictation) ?? [:]
        microphones = try values.decodeIfPresent([String: MicrophonePreference].self, forKey: .microphones) ?? [:]
        remotePreferences = try values.decodeIfPresent([String: RemotePreferences].self, forKey: .remotePreferences) ?? [:]
        bindingSets = try values.decodeIfPresent([String: [Binding]].self, forKey: .bindingSets) ?? [:]
        migrateLegacyAppNamespace()
    }
    private mutating func migrateLegacyAppNamespace() {
        let legacy="org.justviberemote.app.codex",current="org.justviberemote.app.chatgpt"
        if appPluginID == legacy {
            let currentKey=devicePluginID + "|" + current
            if let saved=appMappings[currentKey] { self=saved.apply(to:self) }
            else if let saved=bindingSets[currentKey] { bindings=saved }
            appPluginID=current
        }
        for key in Array(bindingSets.keys) where key.hasSuffix("|" + legacy) {
            let replacement=String(key.dropLast(legacy.count)) + current
            if bindingSets[replacement] == nil { bindingSets[replacement]=bindingSets[key] }
            bindingSets.removeValue(forKey:key)
        }
        for key in Array(appMappings.keys) where key.hasSuffix("|" + legacy) {
            let replacement=String(key.dropLast(legacy.count)) + current
            if appMappings[replacement] == nil { appMappings[replacement]=appMappings[key] }
            appMappings.removeValue(forKey:key)
        }
        for deviceID in Array(remotePreferences.keys) where remotePreferences[deviceID]?.selectedAppID == legacy {
            remotePreferences[deviceID]?.selectedAppID=current
        }
    }
    func validate() throws {
        try self.profile.validate()
        guard remotePreferences.count <= 256, cursorSettings.count <= 256 else { throw JustVibeRemoteError.message("Too many remote or cursor profiles.") }
        for setting in cursorSettings.values { try setting.validate() }
        guard systemDictation.count<=256 else { throw JustVibeRemoteError.message("Too many dictation profiles.") }
        for setting in systemDictation.values { try setting.validate() }
        guard self.schemaVersion == 1, (1...64).contains(self.bindings.count),
              ["hold", "toggle"].contains(self.voiceMode), self.appMappings.count <= 256,
              self.appMappings.values.allSatisfy({ (1...64).contains($0.bindings.count) && ["hold", "toggle"].contains($0.voiceMode) }),
              self.bindingSets.values.allSatisfy({ (1...64).contains($0.count) }) else {
            throw JustVibeRemoteError.message("Unsupported or invalid settings. Your settings file has been preserved.")
        }
    }
}

/// The keyboard shortcut channel is shared by all remotes. Only the owner
/// may release a held dictation shortcut; other remote sessions stay connected.
final class RemoteVoiceOwnership {
    private(set) var owner: String?
    func claim(_ remoteID: String) -> Bool {
        guard owner == nil || owner == remoteID else { return false }
        owner = remoteID;return true
    }
    func release(_ remoteID: String) { if owner == remoteID { owner = nil } }
    func allows(_ remoteID: String) -> Bool { owner == nil || owner == remoteID }
}

final class ConfigurationStore {
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JustVibeRemote/settings.json")
    }
    func load(defaults: Configuration = Configuration()) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaults }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }
    /// Compatibility for explicit diagnostics that used the old single file.
    func loadCurrentRemote(defaults: Configuration = Configuration()) throws -> Configuration {
        let legacy = try load(defaults: defaults)
        guard legacy.devicePluginID.range(of: #"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$"#, options: .regularExpression) != nil, legacy.devicePluginID.count <= 150 else {
            throw JustVibeRemoteError.message("Invalid remote identity in saved settings. The settings file was preserved.")
        }
        let remote = url.deletingLastPathComponent().appendingPathComponent("remotes").appendingPathComponent(legacy.devicePluginID).appendingPathComponent("settings.json")
        return try ConfigurationStore(url: remote).load(defaults: legacy)
    }
    func save(_ config: Configuration) throws {
        try config.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
enum JustVibeRemoteError: LocalizedError {
    case message(String)
    case deviceUnavailable
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .deviceUnavailable: return "Receiver mapping service is unavailable. Reconnect the receiver and try Start again."
        }
    }
}

/// Pure state machine. OS code carries out each transition, then commits it.
/// A failed key injection must never mark a shortcut as held or released.
struct VoiceSession {
    private(set) var held = false
    private(set) var startedAt: TimeInterval = 0
    mutating func commit(_ active: Bool, now: TimeInterval) {
        held = active
        if active { startedAt = now }
    }
    func desiredState(down: Bool, mode: String) -> Bool? {
        if mode == "toggle" { return down ? !held : nil }
        return down == held ? nil : down
    }
    func expired(now: TimeInterval) -> Bool { held && now - startedAt >= 120 }
}

/// A toggle owns two complete taps. Retrying a failed key-up must never send
/// another key-down and accidentally restart dictation.
struct ToggleShortcutLease {
    private(set) var active=false
    private(set) var pendingKeyUp=false
    private(set) var stopSent=false
    mutating func start(down:() throws -> Void,up:() throws -> Void) throws {
        guard !active else { return }
        try down();active=true;pendingKeyUp=true;stopSent=false
        try up();pendingKeyUp=false
    }
    mutating func stop(down:() throws -> Void,up:() throws -> Void,releaseStart:(() throws -> Void)? = nil) throws {
        guard active else { return }
        if pendingKeyUp && !stopSent {
            if let releaseStart { try releaseStart() } else { try up() }
            pendingKeyUp=false
        }
        if !stopSent { try down();stopSent=true;pendingKeyUp=true }
        if pendingKeyUp { try up();pendingKeyUp=false }
        active=false
    }
}

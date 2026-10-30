import Foundation

struct PluginTarget: Codable {
    let bundleIds: [String]
    let names: [String]
}
struct PluginAction: Codable {
    let operation: String
    let shortcuts: [String: String]?
}
struct DevicePlugin: Codable { let adapter: String; let profile: DeviceProfile; let layout: RemoteLayout? }
struct AppPlugin: Codable {
    let adapter: String
    let targets: [String: PluginTarget]
    let actions: [String: PluginAction]
    func shortcut(_ action: RemoteAction, platform: String = "macos") throws -> String {
        guard let value = actions[action.rawValue]?.shortcuts?[platform] else {
            throw JustVibeRemoteError.message("The selected app plugin does not provide this shortcut.")
        }
        return value
    }
    func supports(_ action: RemoteAction) -> Bool { action == .native || actions[action.rawValue] != nil }
}
struct PluginManifest: Codable {
    let schemaVersion: Int
    let apiVersion: Int
    let id: String
    let version: String
    let name: String
    let author: String
    let kind: String
    let platforms: [String]
    let capabilities: [String]
    let device: DevicePlugin?
    let app: AppPlugin?

    func validate() throws {
        func require(_ value: Bool, _ message: String) throws { if !value { throw JustVibeRemoteError.message(message) } }
        try require((schemaVersion == 1 && apiVersion == 1 && device?.layout == nil) || (schemaVersion == 2 && apiVersion == 2 && kind == "device" && device?.layout != nil) || (schemaVersion == 3 && apiVersion == 3 && kind == "app" && platforms == ["macos"]), "Unsupported plugin schema or host API version")
        try require(id.range(of: #"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$"#, options: .regularExpression) != nil && id.count <= 150, "Invalid plugin ID")
        try require(version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil && version.count <= 64, "Invalid plugin version")
        try require(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100 && !author.isEmpty && author.count <= 150, "Plugin name and author are required")
        try require(!platforms.isEmpty && Set(platforms).isSubset(of: ["macos", "windows"]) && Set(platforms).count == platforms.count, "Invalid plugin platforms")
        if kind == "device" {
            try require(device?.adapter == "hid.standard" && app == nil, "Invalid device adapter or mixed plugin kinds")
            try require(Set(capabilities) == (device!.profile.audio == "none" ? ["hid.standard"] : ["hid.standard", "audio.native-input"]) && capabilities.count == Set(capabilities).count, "Unsupported device capabilities")
            try device!.profile.validate()
            try device!.layout?.validate()
        } else if kind == "app" {
            try require(app?.adapter == "shortcuts" && device == nil, "Invalid app adapter or mixed plugin kinds")
            try require(Set(capabilities) == ["target.focus", "input.shortcuts"] && capabilities.count == Set(capabilities).count, "Unsupported app capabilities")
            let app = app!
            try require(Set(app.targets.keys).isSubset(of: ["macos", "windows"]), "Unknown target platform")
            for platform in platforms {
                guard let target = app.targets[platform] else { throw JustVibeRemoteError.message("Missing target for \(platform)") }
                try require(!target.names.isEmpty || (platform == "macos" && !target.bundleIds.isEmpty), "Target identities are required")
                try require((target.names + target.bundleIds).allSatisfy { !$0.isEmpty && $0.count <= 150 && !$0.contains("/") && !$0.contains("\\") }, "Target identities must be names, not paths")
            }
            try require(app.actions["focus"]?.operation == "focus", "App plugins must provide focus")
            for (key, action) in app.actions {
                guard let intent = RemoteAction(rawValue: key), intent != .native else { throw JustVibeRemoteError.message("Unknown app action") }
                let expected = intent == .focus ? "focus" : intent == .dictate ? "hold-shortcut" : "tap-shortcut"
                let toggle=intent == .dictate && action.operation == "toggle-shortcut" && schemaVersion == 3 && apiVersion == 3 && platforms == ["macos"]
                try require(action.operation == expected || toggle, "Unsupported action operation")
                if intent == .focus {
                    try require(action.shortcuts == nil, "Focus cannot execute a shortcut")
                } else {
                    try require(Set(action.shortcuts?.keys.map { $0 } ?? []).isSubset(of: Set(platforms)), "Unknown shortcut platform")
                    for platform in platforms {
                        guard let shortcut = action.shortcuts?[platform] else { throw JustVibeRemoteError.message("Missing action shortcut") }
                        try Self.validateShortcut(shortcut, platform: platform)
                    }
                }
            }
        } else { throw JustVibeRemoteError.message("Unknown plugin kind") }
    }
    static func validateShortcut(_ shortcut: String, platform: String) throws {
        let tokens = shortcut.uppercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let common = Set(["CTRL", "CONTROL", "SHIFT", "ALT", "SPACE", "RETURN", "ENTER", "ESC", "BACKSPACE"])
        let allowed = common.union(platform == "macos" ? ["OPTION", "CMD", "COMMAND"] : ["RALT", "WIN"])
        guard !tokens.isEmpty, tokens.count <= 5, tokens.allSatisfy({ allowed.contains($0) || ($0.count == 1 && $0.range(of: "^[A-Z]$", options: .regularExpression) != nil) }) else {
            throw JustVibeRemoteError.message("Unsupported shortcut in plugin")
        }
        if platform == "macos" {
            let final = tokens.last!
            guard ["SPACE", "RETURN", "ENTER", "ESC", "BACKSPACE"].contains(final) || final.count == 1,
                  tokens.dropLast().allSatisfy({ ["CTRL", "CONTROL", "SHIFT", "ALT", "OPTION", "CMD", "COMMAND"].contains($0) }) else {
                throw JustVibeRemoteError.message("macOS shortcuts require modifiers followed by one key")
            }
        }
    }
    static func decode(_ data: Data) throws -> PluginManifest {
        guard data.count <= 65_536 else { throw JustVibeRemoteError.message("Manifest exceeds 64 KiB") }
        // Reject executable-looking and misspelled fields rather than silently
        // ignoring them. Plugin v1 is a data format, never executable code.
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        func keys(_ object: [String: Any], _ allowed: Set<String>) throws {
            guard Set(object.keys).isSubset(of: allowed) else { throw JustVibeRemoteError.message("Unknown manifest field") }
        }
        try keys(root, ["schemaVersion", "apiVersion", "id", "version", "name", "author", "kind", "platforms", "capabilities", "device", "app"])
        if let device = root["device"] as? [String: Any] {
            try keys(device, ["adapter", "profile", "layout"])
            if let layout = device["layout"] as? [String: Any] {
                try keys(layout, ["version", "width", "height", "bodyStyle", "description", "dpad", "buttons"])
                if let disc = layout["dpad"] as? [String: Any] { try keys(disc, ["x", "y", "radius"]) }
                if let controls = layout["buttons"] as? [[String: Any]] {
                    for control in controls {
                        try keys(control, ["id", "label", "icon", "shape", "bounds", "text", "hint", "usage", "defaultAction"])
                        if let bounds = control["bounds"] as? [String: Any] { try keys(bounds, ["x", "y", "width", "height"]) }
                        if let usage = control["usage"] as? [String: Any] { try keys(usage, ["page", "code"]) }
                    }
                }
            }
            if let profile = device["profile"] as? [String: Any] { try keys(profile, ["schemaVersion", "id", "name", "vendorId", "productId", "audio", "consumerReportId", "consumerReportLength", "consumerUsageOffset"]) }
        }
        if let app = root["app"] as? [String: Any] {
            try keys(app, ["adapter", "targets", "actions"])
            if let targets = app["targets"] as? [String: [String: Any]] {
                for target in targets.values { try keys(target, ["bundleIds", "names"]) }
            }
            if let actions = app["actions"] as? [String: [String: Any]] {
                for action in actions.values { try keys(action, ["operation", "shortcuts"]) }
            }
        }
        let result = try JSONDecoder().decode(PluginManifest.self, from: data)
        try result.validate()
        return result
    }
}

struct PluginCatalog {
    private(set) var plugins: [PluginManifest] = []
    private(set) var diagnostics: [String] = []
    var devices: [PluginManifest] { plugins.filter { $0.kind == "device" } }
    var apps: [PluginManifest] { plugins.filter { $0.kind == "app" } }
    func find(_ id: String, kind: String) throws -> PluginManifest {
        guard let plugin = plugins.first(where: { $0.id == id && $0.kind == kind }) else {
            throw JustVibeRemoteError.message("Selected \(kind) plugin is missing or invalid. Choose an installed plugin and save settings.")
        }
        return plugin
    }
    func addingApp(_ app:PluginManifest) throws -> PluginCatalog {
        try app.validate()
        guard app.kind == "app",app.platforms.contains("macos"),!plugins.contains(where:{$0.id == app.id}) else {
            throw JustVibeRemoteError.message("This app profile is invalid or already installed.")
        }
        var result=self;result.plugins.append(app);result.plugins.sort { $0.id < $1.id };return result
    }
    init(bundled: URL, user: URL, platform: String = "macos") {
        let fm = FileManager.default
        func scan(_ root: URL) -> [PluginManifest] {
            let directories = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
            var result: [PluginManifest] = []
            for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                do {
                    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                    let manifest = directory.appendingPathComponent("plugin.json")
                    let metadata = try manifest.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                    guard metadata.isSymbolicLink != true, (metadata.fileSize ?? Int.max) <= 65_536 else { throw JustVibeRemoteError.message("Manifest is a symlink or exceeds 64 KiB") }
                    let plugin = try PluginManifest.decode(Data(contentsOf: manifest))
                    if plugin.platforms.contains(platform) { result.append(plugin) }
                } catch { diagnostics.append("\(directory.lastPathComponent): \(error.localizedDescription)") }
            }
            return result
        }
        let builtins = scan(bundled)
        let reserved = Set(builtins.map(\.id))
        let users = scan(user)
        for (id, candidates) in Dictionary(grouping: builtins, by: \.id) {
            if candidates.count == 1 { plugins.append(candidates[0]) }
            else { diagnostics.append("Duplicate bundled plugin ID: \(id)") }
        }
        for (id, candidates) in Dictionary(grouping: users, by: \.id) {
            if reserved.contains(id) { diagnostics.append("User plugin cannot override bundled ID: \(id)") }
            else if candidates.count != 1 { diagnostics.append("Duplicate user plugin ID disabled: \(id)") }
            else { plugins.append(candidates[0]) }
        }
        plugins.sort { $0.id < $1.id }
    }
}

/// Selection is pure: resolve both IDs before changing configuration, and keep
/// learned bindings isolated by the selected device/app pair.
enum PluginSelection {
    /// Opening a remote restores its own last app rather than carrying the
    /// previously edited remote's app into this workspace.
    static func selectRemote(_ config: Configuration, catalog: PluginCatalog, deviceID: String) throws -> Configuration {
        let preferred = deviceID == config.devicePluginID ? config.appPluginID : config.remotePreferences[deviceID]?.selectedAppID
        let appID = preferred == Configuration.noSpecificAppID ? Configuration.noSpecificAppID : catalog.apps.first(where: { $0.id == preferred })?.id
            ?? catalog.apps.first(where: { $0.id == config.appPluginID })?.id
            ?? catalog.apps.first?.id
        guard let appID else { throw JustVibeRemoteError.message("Install an app plugin before configuring this remote.") }
        return try select(config, catalog: catalog, deviceID: deviceID, appID: appID)
    }

    static func select(_ config: Configuration, catalog: PluginCatalog, deviceID: String, appID: String) throws -> Configuration {
        let device = try catalog.find(deviceID, kind: "device")
        let app = appID == Configuration.noSpecificAppID ? nil : try catalog.find(appID, kind: "app")
        let actions=app?.app ?? AppRouting.sharedActions
        let configuredPair=config.appPluginID == appID && config.devicePluginID == deviceID || config.bindingSets[AppRouting.key(deviceID,appID)] != nil || config.appMappings[AppRouting.key(deviceID,appID)] != nil
        var next = config
        next.suppressOriginal = true
        next.remotePreferences[config.devicePluginID] = RemotePreferences(config)
        if deviceID != config.devicePluginID {
            let preferences = config.remotePreferences[deviceID]
            next.followActiveApp = preferences?.followActiveApp ?? true
            next.autoConnect = preferences?.autoConnect ?? false
            next.remoteSetupCompleted = preferences?.setupCompleted ?? false
            next.remoteSetupCheckpoint = preferences?.setupCheckpoint
        }
        next.bindingSets[config.devicePluginID + "|" + config.appPluginID] = config.bindings
        next.appMappings[AppRouting.key(config.devicePluginID, config.appPluginID)] = AppMapping(config)
        next.profile = device.device!.profile
        if deviceID != config.devicePluginID || appID != config.appPluginID {
            next.bindings = try next.bindingSets[deviceID + "|" + appID] ?? device.device!.layout?.bindings() ?? Binding.initial
        }
        if deviceID != config.devicePluginID || appID != config.appPluginID {
            if let saved = next.appMappings[AppRouting.key(deviceID, appID)] { next = saved.apply(to: next) }
            else {
                next.shortcut = (try? app?.app?.shortcut(.dictate)) ?? ""; next.shortcutConfirmed = false
                next.targetAppPath = ""; next.dictationTested = false; next.voiceMode = "toggle"
                // Signals identify the physical device, so carry them to a new app's layout.
                if deviceID == config.devicePluginID && config.bindingSets[AppRouting.key(deviceID, appID)] == nil {
                    next.bindings = next.bindings.map { binding in
                        var result = binding
                        if let learned = config.bindings.first(where: { binding.controlID != nil ? ($0.controlID == binding.controlID || ($0.controlID == nil && $0.name == binding.name)) : $0.name == binding.name }) { result.usage = learned.usage }
                        return result
                    }
                }
            }
        }
        if let layout = device.device!.layout { next.bindings = try layout.bindings(preserving: next.bindings) }
        next.bindings = next.bindings.map { binding in
            var result = binding
            if (result.action != .focus && !actions.supports(result.action)) || (appID == Configuration.noSpecificAppID && !configuredPair) { result.action = .native }
            return result
        }
        next.devicePluginID = deviceID
        next.appPluginID = appID
        next.remotePreferences[deviceID] = RemotePreferences(next)
        return next
    }
}

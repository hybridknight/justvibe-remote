import Foundation

/// The editor selects a controller; it does not own or stop other controllers.
/// Each receiver has a separate settings file and restoration journals.
final class RemoteSessions {
    private(set) var controllers: [String: RemoteController] = [:]
    private(set) var catalog: PluginCatalog
    let pluginDirectory: URL
    private let root: URL
    private let bundled: URL
    private let legacy: Configuration
    private let voiceOwnership = RemoteVoiceOwnership()
    var changed: (() -> Void)?
    var initial: RemoteController? {
        controllers[legacy.devicePluginID] ?? catalog.devices.compactMap { controllers[$0.id] }.first
    }
    var voiceActive: Bool { controllers.values.contains { $0.voiceActive } }

    init(store: ConfigurationStore = ConfigurationStore(), bundledPlugins: URL? = nil) throws {
        root = store.url.deletingLastPathComponent()
        pluginDirectory = root.appendingPathComponent("plugins")
        bundled = bundledPlugins ?? Bundle.main.resourceURL!.appendingPathComponent("plugins")
        catalog = PluginCatalog(bundled: bundled, user: pluginDirectory)
        var defaults = Configuration()
        if let device = try? catalog.find(defaults.devicePluginID, kind: "device") { defaults.profile = device.device!.profile }
        if let app = try? catalog.find(defaults.appPluginID, kind: "app") { defaults.shortcut = (try? app.app!.shortcut(.dictate)) ?? "" }
        legacy = try store.load(defaults: defaults)
        try loadControllers()
    }
    private func loadControllers() throws {
        for device in catalog.devices where controllers[device.id] == nil {
            // Plugin IDs are validated, bounded names without path separators.
            let directory = root.appendingPathComponent("remotes").appendingPathComponent(device.id)
            let defaults = try PluginSelection.selectRemote(legacy, catalog: catalog, deviceID: device.id)
            let session = try RemoteController(store: ConfigurationStore(url: directory.appendingPathComponent("settings.json")),
                                               defaults: defaults, pluginDirectory: pluginDirectory, bundledPlugins: bundled, sessionDeviceID: device.id)
            session.validateStart = { [weak self, weak session] in
                guard let self, let session else { return }
                if self.controllers.values.contains(where: { $0 !== session && $0.running && $0.config.profile.hardwareID == session.config.profile.hardwareID }) {
                    throw JustVibeRemoteError.message("Another active remote uses the same receiver hardware ID. These receiver profiles cannot be separated by the current device adapter.")
                }
            }
            session.claimVoice = { [weak self] in self?.voiceOwnership.claim(device.id) ?? false }
            session.releaseVoice = { [weak self] in self?.voiceOwnership.release(device.id) }
            session.maySendOutput = { [weak self] in self?.voiceOwnership.allows(device.id) ?? false }
            session.changed = { [weak self] in self?.changed?() }
            controllers[device.id] = session
        }
    }
    func activate() throws {
        // Restore journals written by the previous single-session app before
        // any independent sessions take ownership of their receivers.
        try MappingLease(directory: root).restore()
        try CursorSpeedControl(directory: root).restore()
        for session in controllers.values { try session.recoverSession();session.resumeIfConfigured() }
    }
    func addApp(_ application:LocalAppRegistration,dictationShortcut:String? = nil) throws -> PluginManifest {
        let existing=catalog.apps.filter { $0.app?.targets["macos"]?.bundleIds.contains(application.bundleID) == true }
        if existing.count == 1 { return existing[0] }
        guard existing.isEmpty else { throw JustVibeRemoteError.message("Several profiles already target this app. Choose one in Apps and use Locate app to distinguish it.") }
        let plugin=try application.manifest(dictationShortcut:dictationShortcut)
        let updated=try catalog.addingApp(plugin)
        try LocalAppRegistration.install(plugin,in:pluginDirectory)
        // Publish only the new app. Never reload devices or interrupt other remotes.
        catalog=updated
        for session in controllers.values { try session.registerApp(plugin) }
        changed?()
        return plugin
    }
    func stopVoices() { controllers.values.forEach { $0.stopVoice() } }
    func shutdown() throws {
        var failure: Error?
        for session in controllers.values {
            do { try session.shutdown() } catch { failure = failure ?? error }
        }
        if let failure { throw failure }
    }
    func reload() throws {
        // Global plugin maintenance explicitly stops every session. Merely
        // browsing or editing another remote never takes this path.
        try shutdown()
        catalog = PluginCatalog(bundled: bundled, user: pluginDirectory)
        for id in Array(controllers.keys) {
            if catalog.devices.contains(where: { $0.id == id }) { try controllers[id]?.reloadPlugins() }
            else { controllers.removeValue(forKey: id) }
        }
        try loadControllers()
        changed?()
    }
}

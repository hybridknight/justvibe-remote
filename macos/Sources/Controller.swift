import AppKit

final class RemoteController {
    let store: ConfigurationStore
    let artwork: RemoteArtworkStore
    private let sessionDeviceID: String?
    var validateStart: (() throws -> Void)?
    var claimVoice: (() -> Bool)?
    var releaseVoice: (() -> Void)?
    var maySendOutput: (() -> Bool)?
    private(set) var config: Configuration
    private(set) var catalog: PluginCatalog
    let pluginDirectory: URL
    private let bundledPlugins: URL
    var appPlugin: PluginManifest? { try? catalog.find(config.appPluginID, kind: "app") }
    var devicePlugin: PluginManifest? { try? catalog.find(config.devicePluginID, kind: "device") }
    var remoteLayout: RemoteLayout { devicePlugin?.device?.layout ?? RemoteLayout.generic(config.bindings) }
    private(set) var activeUsages = Set<Usage>()
    private(set) var buttonTest=ButtonTestState()
    var buttonTestMode:Bool { buttonTest.enabled }
    private(set) var buttonTestFailure:String?
    var displayedUsages:Set<Usage> { buttonTest.highlights(active:activeUsages,now:ProcessInfo.processInfo.systemUptime) }
    private var testHeldUsages=Set<Usage>()
    private var testUsingMappings=false
    private func isolateTestButtons() throws {
        try mappings.apply(profile:config.profile,groups:input.interfaceGroups,sources:Set(input.testButtonUsages.map(\.hidutilCode)),testMode:true)
        testUsingMappings=true
    }
    private func openButtonCapture(_ enabled:Bool) throws -> String? {
        testUsingMappings=false
        return try ButtonTestCapture.transition(enabled:enabled,isolate:{ try self.isolateTestButtons() },reopen:{ try self.input.start(self.config.profile,exclusive:$0) })
    }
    func setButtonTestMode(_ enabled:Bool) {
        if !enabled { buttonTestFailure=nil }
        guard enabled != buttonTestMode, !(enabled && buttonTestFailure != nil) else { return }
        // Mark the mode first so callbacks cannot dispatch actions during transition.
        if !enabled { testHeldUsages.formUnion(activeUsages) }
        buttonTest.setEnabled(enabled)
        let previousStatus=status
        let hadVoice=voiceActive || output.hasVoiceOutput
        cancelDeleteRepeat();cancelLearning();finishVoice()
        if !hadVoice { status=previousStatus }
        activeUsages.removeAll()
        guard running else { changed?();return }
        do {
            guard !voiceActive else { throw JustVibeRemoteError.message("Dictation could not be stopped. Reconnect before testing.") }
            try mappings.restore();mappingReady=false
            let failure=try openButtonCapture(enabled)
            if let failure {
                // Retain the normal connection, but never claim unsuppressed input is a test.
                buttonTestFailure=failure;buttonTest.setEnabled(false)
                synchronizeRoute(force:true)
                status="Button test unavailable; normal remote connection restored. " + failure
            } else if enabled { status="Test mode · button actions paused" }
            else { synchronizeRoute(force:true) }
        } catch {
            // Never fall back to unsuppressed native input while claiming test mode.
            let failure=error.localizedDescription
            try? stop();status="Remote disconnected: " + failure
        }
        changed?()
    }
    var learningIndex: Int? { learning }
    var voiceActive: Bool { voice.held || pendingVoice }
    private(set) var dictationStopSummary="Stop timing appears after your next remote dictation stop."
    var actionPlugin:AppPlugin? { config.appPluginID == Configuration.noSpecificAppID ? AppRouting.sharedActions:appPlugin?.app }
    var availableActions: [RemoteAction] { RemoteAction.allCases.filter { actionPlugin?.supports($0) == true || $0 == .native } }
    var systemDictationSettings:SystemDictationSettings { config.systemDictation[config.devicePluginID] ?? SystemDictationSettings() }
    var systemDictationSummary:String {
        let setting=systemDictationSettings
        guard setting.enabled else { return "Off · use macOS Dictation in text fields across apps." }
        return (setting.mode == .everywhere ? "Every app":"Fallback for apps without configured dictation") + " · " + setting.shortcutDescription
    }
    func saveSystemDictation(_ setting:SystemDictationSettings) throws {
        try setting.validate()
        if setting.mode != .off {
            guard config.bindings.contains(where:{$0.controlID == setting.controlID && $0.usage != nil}) else {
                throw JustVibeRemoteError.message("Link the selected physical button on the Buttons page first.")
            }
        }
        var next=config;next.systemDictation[next.devicePluginID]=setting
        try update(next)
    }

    private var cursorControl: CursorSpeedControl?
    private var cursorActive = false
    private var cursorLastFailure: String?
    private(set) var cursorSettingsOpen = false
    func recoverSession() throws {
        try mappings.restore()
        try cursorControl?.restore()
    }
    func activateCursorSupport() {
        cursorActive=true
        configureCursor()
    }
    private func configureCursor() {
        guard cursorActive else { return }
        do {
            guard let cursorControl else { throw JustVibeRemoteError.message(cursorLastFailure ?? "Cursor controls are unavailable.") }
            try cursorControl.configure(profile:config.profile,setting:config.cursorSettings[config.devicePluginID]);cursorLastFailure=nil
        } catch { cursorLastFailure=error.localizedDescription }
    }
    func currentCursorSpeed() throws -> Double {
        guard let cursorControl else { throw JustVibeRemoteError.message(cursorLastFailure ?? "Cursor controls are unavailable.") }
        return try cursorControl.current(config.profile)
    }
    func currentCursorLinear() throws -> Bool {
        guard let cursorControl else { throw JustVibeRemoteError.message(cursorLastFailure ?? "Cursor controls are unavailable.") }
        return try cursorControl.currentLinear(config.profile)
    }
    func previewCursorSpeed(_ setting: CursorSpeedSettings) throws {
        guard let cursorControl else { throw JustVibeRemoteError.message(cursorLastFailure ?? "Cursor controls are unavailable.") }
        try cursorControl.preview(profile:config.profile,setting:setting)
    }
    func saveCursorSpeed(_ setting: CursorSpeedSettings) throws {
        var next=config;next.cursorSettings[next.devicePluginID]=setting
        try update(next);configureCursor()
        if let cursorLastFailure { throw JustVibeRemoteError.message("Preference saved, but not applied: " + cursorLastFailure) }
    }
    func resetCursorSpeed() throws {
        var next=config;next.cursorSettings.removeValue(forKey:next.devicePluginID);try update(next);configureCursor()
        if let cursorLastFailure { throw JustVibeRemoteError.message(cursorLastFailure) }
    }
    func beginCursorSettings() { cancelDeleteRepeat();cancelLearning();stopVoice();cursorSettingsOpen=true }
    func endCursorSettings() throws { try cursorControl?.finishPreview();cursorSettingsOpen=false }
    func shutdown() throws {
        var failure: Error?
        do { try stop() } catch { failure=error }
        if cursorActive {
            do { try cursorControl?.restore();cursorActive=false } catch { failure=failure ?? error }
        }
        if let failure { throw failure }
    }
    private(set) var microphoneTesting = false
    var microphoneSummary: String {
        guard let mic = config.microphones[config.devicePluginID] else { return "Microphone not selected — open Microphone test" }
        return "Remote mic: \(mic.name) · \(mic.guardDictation ? "system-input safeguard on" : "system-input safeguard off") · app input unverified"
    }
    func beginMicrophoneTest() { cancelDeleteRepeat(); cancelLearning(); stopVoice(); microphoneTesting = true }
    func endMicrophoneTest() { microphoneTesting = false; changed?() }
    var microphoneIndex: Int? { config.bindings.firstIndex { $0.controlID == "microphone" || $0.action == .dictate } }
    var setupProgress: SetupProgress {
        SetupProgress(inputAllowed: RemoteInput.allowed, shortcutsAllowed: TargetOutput.allowed, receiverConnected: running && connected > 0,
                      needsDictation: appPlugin?.app?.supports(.dictate) == true, microphoneLinked: microphoneIndex.map { config.bindings[$0].usage != nil && config.bindings[$0].action == .dictate } ?? false,
                      shortcutConfirmed: config.shortcutConfirmed, testConfirmed: config.dictationTested)
    }
    func resumeIfConfigured() {
        if config.autoConnect && RemoteInput.allowed && TargetOutput.allowed { start() }
    }
    func restartApp() throws {
        try shutdown()
        // Wait for this process to exit before asking Launch Services to reopen.
        // The session lock is close-on-exec, so the helper cannot retain ownership.
        let helper=Process();helper.executableURL=URL(fileURLWithPath:"/bin/sh")
        helper.arguments=["-c", #"i=0; while /bin/kill -0 "$1" 2>/dev/null; do i=$((i+1)); [ "$i" -lt 200 ] || exit 1; /bin/sleep 0.1; done; exec /usr/bin/open "$2""#, "justviberemote-restart",String(ProcessInfo.processInfo.processIdentifier),Bundle.main.bundleURL.path]
        try helper.run()
        NSApp.terminate(nil)
    }

    func showTargetApp() {
        do { let display = TargetOutput(); display.plugin = try catalog.find(config.appPluginID, kind: "app").app; try display.show(config) }
        catch { status = error.localizedDescription; changed?() }
    }
    private let input = RemoteInput()
    private let output = TargetOutput()
    private let mappings: MappingLease
    private var deleteRepeat=BackspaceRepeat()
    private var deleteTimer:Timer?
    private var deleteTarget:String?
    private var voice = VoiceSession()
    private var pendingVoice = false
    private var voiceStopTrigger:VoiceStopTrigger?
    private let microphoneGuardQueue=DispatchQueue(label:"app.justviberemote.microphone-guard",qos:.userInitiated)
    private var microphoneCheckInFlight=false
    private var lastMicrophoneCheck=0.0
    private var generation = 0
    private var learning: Int?
    private var timer: Timer?
    private var mappingReady = false
    private var routedConfig: Configuration?
    private var routeKey = ""
    private var activationObserver: NSObjectProtocol?
    private(set) var routingLabel = "Using selected app"
    private func foreground() -> ForegroundApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return ForegroundApp(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "", path: app.bundleURL?.standardizedFileURL.path ?? "", instance: String(app.processIdentifier))
    }
    private func synchronizeRoute(force: Bool = false) {
        guard running,!buttonTestMode else { return }
        let front = foreground()
        let next = AppRouting.resolve(config, apps: catalog.apps, foreground: front)
        let key = config.followActiveApp || config.appPluginID == Configuration.noSpecificAppID || config.systemDictation[config.devicePluginID]?.enabled == true ? (front?.instance ?? "none") + "|" + (next?.appPluginID ?? "native") : config.appPluginID
        guard force || key != routeKey else { return }
        // Invalidate delayed starts and release the previous app's held shortcut first.
        finishVoice()
        guard !voice.held else { routedConfig = nil; mappingReady = false; return }
        cancelDeleteRepeat()
        routeKey = key; routedConfig = next; mappingReady = false
        output.plugin = next.flatMap { AppRouting.outputPlugin($0,apps:catalog.apps) }
        if config.followActiveApp {
            routingLabel=next.map { route in
                if route.usesSystemDictation { return "Active app: macOS Dictation · \(route.shortcut)" }
                if route.appPluginID == Configuration.noSpecificAppID { return "Active app: shared controls" }
                let name=(try? catalog.find(route.appPluginID,kind:"app"))?.name ?? route.appPluginID
                let hasDictation=route.bindings.contains { $0.action == .dictate }
                return "Active mapping: \(name)" + (hasDictation && !route.shortcut.isEmpty ? " · Dictation \(route.shortcut)":"")
            } ?? "Active app: original remote actions"
        } else { routingLabel=next?.usesSystemDictation == true ? "Active app: macOS Dictation" : config.appPluginID == Configuration.noSpecificAppID ? "Shared controls in the active app":"Using selected app" }
        updateMappings()
        changed?()
    }
    private(set) var running = false
    private(set) var connected = 0
    private(set) var status = "Ready to set up your remote"
    var changed: (() -> Void)?

    init(store: ConfigurationStore = ConfigurationStore(), defaults suppliedDefaults: Configuration? = nil,
         pluginDirectory suppliedPluginDirectory: URL? = nil, bundledPlugins suppliedBundledPlugins: URL? = nil, sessionDeviceID: String? = nil) throws {
        self.store = store;self.sessionDeviceID = sessionDeviceID
        artwork=RemoteArtworkStore(directory:store.url.deletingLastPathComponent())
        pluginDirectory = suppliedPluginDirectory ?? store.url.deletingLastPathComponent().appendingPathComponent("plugins")
        bundledPlugins = suppliedBundledPlugins ?? Bundle.main.resourceURL!.appendingPathComponent("plugins")
        catalog = PluginCatalog(bundled: bundledPlugins, user: pluginDirectory)
        var defaults = Configuration()
        if let device = try? catalog.find(defaults.devicePluginID, kind: "device") { defaults.devicePluginID = device.id; defaults.profile = device.device!.profile }
        if let app = try? catalog.find(defaults.appPluginID, kind: "app") { defaults.appPluginID = app.id; defaults.shortcut = (try? app.app!.shortcut(.dictate)) ?? "" }
        config = try store.load(defaults: suppliedDefaults ?? defaults)
        if let sessionDeviceID, config.devicePluginID != sessionDeviceID {
            throw JustVibeRemoteError.message("This remote’s settings identify a different device. The settings file was preserved.")
        }
        if let layout = (try? catalog.find(config.devicePluginID, kind: "device"))?.device?.layout { config.bindings = try layout.bindings(preserving: FileManager.default.fileExists(atPath: store.url.path) || suppliedDefaults != nil ? config.bindings : []) }
        mappings = try MappingLease(directory: store.url.deletingLastPathComponent())
        do { cursorControl=try CursorSpeedControl(directory:store.url.deletingLastPathComponent()) } catch { cursorLastFailure=error.localizedDescription }
        if let saved = try? Data(contentsOf: store.url), let object = try? JSONSerialization.jsonObject(with: saved) as? [String: Any], object["devicePluginID"] == nil {
            config.devicePluginID = catalog.devices.first(where: { $0.device!.profile.vendorId == config.profile.vendorId && $0.device!.profile.productId == config.profile.productId })?.id ?? ""
        }
        input.onOpenFailure = { [weak self] result in
            guard let self else { return }
            let inputGeneration=self.input.generation
            DispatchQueue.main.async { [weak self] in
                guard let self,self.running,self.input.generation == inputGeneration else { return }
                try? self.stop()
                self.status=String(format:"Receiver connection failed (0x%08X). Reconnect before testing.",UInt32(bitPattern:result))
                self.changed?()
            }
        }
        input.onDeliveredEdge = { [weak self] usage,down,lag in self?.handle(usage,down:down,deliveryDelayMs:lag) }
        input.onDevices = { [weak self] count in
            guard let self else { return }
            self.connected = count
            if self.running,self.buttonTestMode,self.testUsingMappings,count>0 {
                do { try self.isolateTestButtons() }
                catch {
                    let failure=error.localizedDescription
                    self.buttonTestFailure=failure;self.buttonTest.setEnabled(false)
                    try? self.stop();self.status="Button testing stopped: " + failure
                    self.changed?();return
                }
            }
            if self.running {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.updateMappings() }
            }
            self.changed?()
        }
        input.onDisconnected = { [weak self] in
            guard let self else { return }
            self.cancelDeleteRepeat()
            self.finishVoice()
            self.activeUsages.removeAll()
            self.buttonTest.setEnabled(self.buttonTestMode)
            self.mappingReady = false
            self.status = "Receiver disconnected; voice shortcut released"
            self.changed?()
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelDeleteRepeat();self?.synchronizeRoute() }
        output.voiceFailure={ [weak self] error in
            guard let self else { return }
            self.finishVoice();self.status=error.localizedDescription;self.changed?()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.checkSession() }
    }
    deinit { timer?.invalidate();deleteTimer?.invalidate();if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) } }
    func start() {
        guard !running else { return }
        do {
            try validateStart?()
            let device = try catalog.find(config.devicePluginID, kind: "device")
            let app = config.appPluginID == Configuration.noSpecificAppID ? nil : try catalog.find(config.appPluginID, kind: "app")
            config.profile = device.device!.profile
            output.plugin = config.appPluginID == Configuration.noSpecificAppID ? AppRouting.sharedActions:app?.app
            if !RemoteInput.allowed { RemoteInput.requestPermission() }
            if !TargetOutput.allowed { TargetOutput.requestPermission() }
            guard TargetOutput.allowed else { throw JustVibeRemoteError.message("Enable Accessibility for JustVibe Remote, then click Start again.") }
            if let failure=try openButtonCapture(buttonTestMode) {
                buttonTestFailure=failure;buttonTest.setEnabled(false)
            }
            running = true
            activateCursorSupport()
            synchronizeRoute(force: true)
            status = connected > 0 ? "Connected · \(config.profile.hardwareID) · \(connected) receiver interfaces" : "Waiting for \(config.profile.name)…"
        } catch { status = error.localizedDescription }
        changed?()
    }
    func stop() throws {
        cancelDeleteRepeat()
        running = false
        routedConfig = nil; routeKey = ""
        activeUsages.removeAll()
        buttonTest.setEnabled(buttonTestMode)
        learning = nil
        generation += 1
        pendingVoice = false
        var failure: Error?
        do { try output.release(); voice.commit(false, now: Date().timeIntervalSince1970);releaseVoice?() } catch { failure = error }
        input.stop();testUsingMappings=false
        mappingReady = false
        do { try mappings.restore() } catch { failure = failure ?? error }
        if cursorActive {
            do { try cursorControl?.restore();cursorActive=false } catch { failure = failure ?? error }
        }
        connected = 0
        status = failure?.localizedDescription ?? "Stopped; original device mappings restored"
        changed?()
        if let failure { throw failure }
    }
    func update(_ proposed: Configuration) throws {
        var newConfig = proposed
        newConfig.suppressOriginal=true
        newConfig.usesSystemDictation=false;newConfig.systemDictationTargetPID=nil
        if let sessionDeviceID, newConfig.devicePluginID != sessionDeviceID {
            throw JustVibeRemoteError.message("Open the other remote from Remotes to configure it.")
        }
        if newConfig.appPluginID == config.appPluginID && newConfig.devicePluginID == config.devicePluginID && (newConfig.shortcut != config.shortcut || newConfig.shortcutConfirmed != config.shortcutConfirmed || newConfig.targetAppPath != config.targetAppPath || newConfig.voiceMode != config.voiceMode || newConfig.bindings != config.bindings) {
            newConfig.dictationTested = false
        }
        if newConfig.microphones[newConfig.devicePluginID]?.id != config.microphones[newConfig.devicePluginID]?.id {
            newConfig.dictationTested = false
            for key in newConfig.appMappings.keys where key.hasPrefix(newConfig.devicePluginID + "|") { newConfig.appMappings[key]?.dictationTested = false }
        }
        _ = try catalog.find(newConfig.devicePluginID, kind: "device")
        let app = newConfig.appPluginID == Configuration.noSpecificAppID ? nil : try catalog.find(newConfig.appPluginID, kind: "app")
        if app?.app?.supports(.dictate) == true { _ = try MacShortcut.parse(newConfig.shortcut) }
        let cursorChanged=newConfig.devicePluginID != config.devicePluginID || newConfig.cursorSettings[newConfig.devicePluginID] != config.cursorSettings[config.devicePluginID]
        let restart = running
        try stop()
        try store.save(newConfig)
        config = newConfig
        if cursorChanged { configureCursor() }
        if restart { start() }
        changed?()
    }
    func setArtwork(from url:URL) throws { try artwork.importImage(from:url);changed?() }
    func resetArtwork() throws { try artwork.reset();changed?() }
    /// Saving presentation progress must not restart this receiver or affect
    /// the other connected remotes.
    func saveSetupCheckpoint(_ checkpoint: RemoteSetupCheckpoint, completed: Bool? = nil) throws {
        var next=config;next.remoteSetupCheckpoint=checkpoint
        if let completed { next.remoteSetupCompleted=completed }
        try store.save(next);config=next;changed?()
    }
    func selectRemote(deviceID: String) throws {
        try update(PluginSelection.selectRemote(config, catalog: catalog, deviceID: deviceID))
    }
    func selectPlugins(deviceID: String, appID: String) throws {
        try update(PluginSelection.select(config, catalog: catalog, deviceID: deviceID, appID: appID))
    }
    func registerApp(_ app:PluginManifest) throws { catalog=try catalog.addingApp(app) }
    func reloadPlugins() throws {
        try stop()
        catalog = PluginCatalog(bundled: bundledPlugins, user: pluginDirectory)
        if let layout = devicePlugin?.device?.layout { config.bindings = try layout.bindings(preserving: config.bindings) }
        status = "Plugins reloaded; connect your remote when ready. " + catalog.diagnostics.joined(separator: " · ")
        changed?()
    }
    func cancelLearning() { guard learning != nil else { return }; learning = nil; updateMappings(); status = "Button learning cancelled"; changed?() }
    func learn(_ index: Int) {
        guard config.bindings.indices.contains(index) else { return }
        guard running else { status = "Connect your remote before learning a button"; changed?(); return }
        finishVoice()
        cancelDeleteRepeat()
        learning = index
        updateMappings()
        status = "Press only the \(config.bindings[index].name) button once…"
        changed?()
    }
    func stopVoice() { finishVoice() }
    func testVoice() {
        guard !buttonTestMode else { status="Leave the Button test page to try dictation in your app";changed?();return }
        guard running else { status = "Connect your remote first"; changed?(); return }
        if voice.held || pendingVoice { finishVoice() }
        else if config.followActiveApp { showTargetApp(); status = "Use the remote’s microphone button in the app to test its active mapping"; changed?() }
        else if let route = routedConfig { beginVoice(route) }
    }
    private func updateMappings() {
        guard running, connected > 0 else { return }
        if buttonTestMode { mappingReady=false;changed?();return }
        do {
            let sources = Set((learning == nil ? routedConfig?.bindings ?? [] : []).filter { $0.action != .native }.compactMap { $0.usage?.hidutilCode })
            try mappings.apply(profile: config.profile, groups: input.interfaceGroups, sources: sources)
            mappingReady = true
            status = learning == nil ? "Connected · \(config.profile.hardwareID) · app plugin ready" : status
        } catch {
            mappingReady = false
            status = error.localizedDescription
        }
        changed?()
    }
    private func handle(_ usage: Usage, down: Bool, deliveryDelayMs:Double? = nil) {
        guard running else { return }
        let receivedAt=ProcessInfo.processInfo.systemUptime
        if down {
            cancelDeleteRepeat()
            activeUsages.insert(usage)
        } else {
            deleteRepeat.release(usage)
            if deleteRepeat.usage == nil { cancelDeleteRepeat() }
            activeUsages.remove(usage)
        }
        if buttonTestMode {
            buttonTest.observe(usage,down:down,now:receivedAt)
            if down {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.45) { [weak self] in self?.changed?() }
            }
        }
        if !buttonTestMode,testHeldUsages.contains(usage) {
            if !down { testHeldUsages.remove(usage) }
            changed?();return
        }
        // Key-up comes before UI refresh, route lookup, remapping, or audio work.
        if voiceStopTrigger?.shouldStop(usage:usage,down:down,active:voiceActive)==true {
            finishVoice(remoteReceivedAt:receivedAt,deliveryDelayMs:deliveryDelayMs);return
        }
        changed?()
        if let index = learning {
            guard down else { return }
            var next=config;next.linkButton(at:index,to:usage)
            learning = nil
            do { try store.save(next);config=next;synchronizeRoute(force: true);status = "Linked \(config.bindings[index].name) for all apps on this remote: \(usage.label)" }
            catch { status = error.localizedDescription }
            changed?()
            return
        }
        guard !buttonTestMode && !microphoneTesting && !cursorSettingsOpen else { return }
        synchronizeRoute()
        guard mappingReady, let route = routedConfig, let binding = route.bindings.first(where: { $0.usage == usage }) else { return }
        guard output.plugin?.supports(binding.action) == true else { return }
        if binding.action == .dictate {
            if route.voiceMode == "hold", !down { finishVoice(); return }
            if down {
                if route.voiceMode == "toggle", voice.held || pendingVoice { finishVoice() }
                else if !voice.held && !pendingVoice { beginVoice(route,triggerUsage:usage) }
            }
            return
        }
        guard down else { return }
        do {
            guard maySendOutput?() != false else { throw JustVibeRemoteError.message("Another remote is dictating. Finish its voice input before sending app shortcuts.") }
            if binding.action == .focus { try output.show(route) }
            else if binding.action != .native {
                guard output.isTargetFrontmost(route) else { throw JustVibeRemoteError.message("Switch to the selected app before using mapped typing buttons.") }
                try output.tap(binding.action)
                if binding.action == .backspace { beginDeleteRepeat(usage) }
            }
        } catch { status = error.localizedDescription; changed?() }
    }
    private func cancelDeleteRepeat() {
        deleteRepeat.cancel();deleteTimer?.invalidate();deleteTimer=nil;deleteTarget=nil
    }
    private func beginDeleteRepeat(_ usage:Usage) {
        cancelDeleteRepeat()
        guard let target=foreground()?.instance else{return}
        deleteTarget=target;deleteRepeat.start(usage,now:ProcessInfo.processInfo.systemUptime)
        let timer=Timer(timeInterval:0.03,repeats:true) { [weak self] _ in self?.repeatDelete() }
        deleteTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    private func repeatDelete() {
        guard running,!buttonTestMode,learning == nil,!microphoneTesting,!cursorSettingsOpen,
              RemoteInput.allowed,TargetOutput.allowed,
              let usage=deleteRepeat.usage,activeUsages.contains(usage),
              let route=routedConfig,foreground()?.instance==deleteTarget,
              output.isTargetFrontmost(route),mappingReady,
              route.bindings.contains(where:{$0.usage==usage && $0.action == .backspace}) else {
            cancelDeleteRepeat();return
        }
        guard maySendOutput?() != false else { cancelDeleteRepeat();return }
        guard deleteRepeat.due(now:ProcessInfo.processInfo.systemUptime) else{return}
        do { try output.tap(.backspace) }
        catch { cancelDeleteRepeat();status=error.localizedDescription;changed?() }
    }
    private func beginVoice(_ route: Configuration,triggerUsage:Usage? = nil) {
        do {
            guard !buttonTestMode && !microphoneTesting && !cursorSettingsOpen else { throw JustVibeRemoteError.message("Close the microphone test or cursor settings before starting dictation.") }
            try AudioInputs.check(config.microphones[config.devicePluginID])
            guard output.plugin?.supports(.dictate) == true else { throw JustVibeRemoteError.message("This app plugin does not provide dictation.") }
            guard route.shortcutConfirmed else { throw JustVibeRemoteError.message("Match the shortcut to the selected app’s dictation setting, then check Confirmed.") }
            if route.usesSystemDictation { try systemDictationSettings.validate() }
            else { _ = try MacShortcut.parse(route.shortcut) }
            guard claimVoice?() != false else { throw JustVibeRemoteError.message("Another remote is using voice input. Stop its dictation before starting here.") }
            if route.followActiveApp || route.usesSystemDictation {
                guard output.isTargetFrontmost(route) else { throw JustVibeRemoteError.message("The active app changed. Press the remote button again in your app.") }
            } else { try output.show(route) }
            generation += 1
            let ticket = generation
            pendingVoice = true
            voiceStopTrigger=(triggerUsage ?? route.bindings.first(where:{$0.action == .dictate && $0.usage != nil})?.usage).map { VoiceStopTrigger(usage:$0,mode:route.voiceMode) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                self.synchronizeRoute()
                guard self.running, self.pendingVoice, self.generation == ticket else { return }
                self.pendingVoice = false
                do {
                    guard self.output.isTargetFrontmost(route) else { throw JustVibeRemoteError.message("The selected app is not in front. Open it and try again.") }
                    guard !self.buttonTestMode && !self.microphoneTesting && !self.cursorSettingsOpen else { return }
                    try AudioInputs.check(self.config.microphones[self.config.devicePluginID])
                    try self.output.beginDictation(route,operation:self.output.plugin?.actions["dictate"]?.operation ?? "hold-shortcut")
                    self.voice.commit(true, now: Date().timeIntervalSince1970)
                    self.status = (route.usesSystemDictation ? "macOS Dictation start shortcut sent · ":"Dictation started · ") + self.microphoneSummary
                } catch {
                    if self.output.hasVoiceOutput {
                        self.voice.commit(true,now:Date().timeIntervalSince1970)
                        self.finishVoice()
                    } else { self.releaseVoice?() }
                    self.status = error.localizedDescription
                }
                self.changed?()
            }
        } catch {
            if !voice.held && !pendingVoice { releaseVoice?() }
            status = error.localizedDescription; changed?()
        }
    }
    private func finishVoice(remoteReceivedAt:TimeInterval? = nil,deliveryDelayMs:Double? = nil) {
        generation += 1
        let wasHeld=voice.held
        pendingVoice = false
        do {
            try output.release()
            voice.commit(false, now: Date().timeIntervalSince1970)
            voiceStopTrigger=nil
            releaseVoice?()
            if let remoteReceivedAt {
                let elapsed=(ProcessInfo.processInfo.systemUptime-remoteReceivedAt)*1000
                status=wasHeld ? String(format:"Dictation stop sent in %.1f ms",elapsed) : "Pending dictation start cancelled"
                if let deliveryDelayMs { status += String(format:" · input queue %.1f ms",deliveryDelayMs) }
                dictationStopSummary=status+". This measures shortcut posting, not the app’s response."
            } else { status = "Dictation stopped" }
        } catch { status = error.localizedDescription }
        changed?()
    }
    private func checkMicrophoneWhileSpeaking() {
        let now=ProcessInfo.processInfo.systemUptime
        guard voice.held,!microphoneCheckInFlight,now-lastMicrophoneCheck>=0.5,
              let preference=config.microphones[config.devicePluginID],preference.guardDictation else{return}
        lastMicrophoneCheck=now;microphoneCheckInFlight=true
        let ticket=generation
        microphoneGuardQueue.async { [weak self] in
            let failure:String? = {
                do { try AudioInputs.check(preference);return nil } catch { return error.localizedDescription }
            }()
            DispatchQueue.main.async { [weak self] in
                guard let self else{return};self.microphoneCheckInFlight=false
                guard self.generation==ticket,self.voice.held,let failure else{return}
                self.finishVoice();self.status=failure;self.changed?()
            }
        }
    }
    private func checkSession() {
        if cursorActive { cursorControl?.poll() }
        synchronizeRoute()
        checkMicrophoneWhileSpeaking()
        if voice.held && (voice.expired(now: Date().timeIntervalSince1970) || !(routedConfig.map { output.isTargetFrontmost($0) } ?? false) || !TargetOutput.allowed) {
            finishVoice()
        }
        if running && (!RemoteInput.allowed || !TargetOutput.allowed) { try? stop() }
    }
}

import Foundation

@main struct CoreTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError("FAIL: \(message)") }
            count += 1
        }
        var events:[String]=[],toggleLease=ToggleShortcutLease()
        try toggleLease.start(down:{events.append("down")},up:{events.append("up")})
        check(toggleLease.active && events == ["down","up"],"toggle dictation starts with one complete tap")
        try toggleLease.start(down:{events.append("extra")},up:{events.append("extra")})
        check(events.count == 2,"starting an active toggle cannot send another tap")
        try toggleLease.stop(down:{events.append("down")},up:{events.append("up")})
        check(!toggleLease.active && events == ["down","up","down","up"],"toggle dictation stops with exactly one second tap")
        try toggleLease.stop(down:{events.append("extra")},up:{events.append("extra")})
        check(events.count == 4,"repeated cleanup never restarts toggled dictation")
        enum InjectionFailure:Error { case unavailable }
        var failedStart=ToggleShortcutLease()
        do { try failedStart.start(down:{throw InjectionFailure.unavailable},up:{});check(false,"failed start was accepted") } catch { check(!failedStart.active,"failed start key-down never acquires dictation state") }
        var partialStart=ToggleShortcutLease();events=[]
        do { try partialStart.start(down:{events.append("start-down")},up:{throw InjectionFailure.unavailable}) } catch {}
        check(partialStart.active && partialStart.pendingKeyUp,"partial start retains ownership for cleanup")
        try partialStart.stop(down:{events.append("stop-down")},up:{events.append("up")})
        check(events == ["start-down","up","stop-down","up"] && !partialStart.active,"partial start releases its key before sending a stop tap")
        var partialStop=ToggleShortcutLease();try partialStop.start(down:{},up:{})
        do { try partialStop.stop(down:{},up:{throw InjectionFailure.unavailable}) } catch {}
        check(partialStop.active && partialStop.stopSent && partialStop.pendingKeyUp,"failed stop key-up stays retryable without another toggle")
        events=[];try partialStop.stop(down:{events.append("wrong-down")},up:{events.append("up")})
        check(events == ["up"] && !partialStop.active,"retrying stop key-up never sends a new key-down")
        var stoppedDown=ToggleShortcutLease();try stoppedDown.start(down:{},up:{})
        do { try stoppedDown.stop(down:{throw InjectionFailure.unavailable},up:{}) } catch {}
        check(stoppedDown.active && !stoppedDown.stopSent,"failed stop key-down retains the original session")
        events=[];try stoppedDown.stop(down:{events.append("down")},up:{events.append("up")})
        check(events == ["down","up"] && !stoppedDown.active,"failed stop can retry exactly one complete stop tap")
        let micUsage=Usage(page:12,code:0x221),otherUsage=Usage(page:7,code:4)
        var deletion=BackspaceRepeat()
        check(!deletion.due(now:1),"idle delete never repeats")
        deletion.start(otherUsage,now:1)
        check(!deletion.due(now:1.39),"short tap has no repeat before initial delay")
        check(deletion.due(now:1.4),"held delete repeats after initial delay")
        check(!deletion.due(now:1.41),"repeat interval limits deletion rate")
        check(deletion.due(now:10),"delayed timer emits one repeat")
        check(!deletion.due(now:10),"delayed timer never catches up in a deletion burst")
        deletion.release(micUsage)
        check(deletion.usage==otherUsage,"unrelated release does not end held delete")
        deletion.release(otherUsage)
        check(!deletion.due(now:11),"release immediately stops repeating")
        deletion.start(otherUsage,now:12);deletion.cancel()
        check(!deletion.due(now:13),"focus or session cancellation prevents further deletes")
        let toggleStop=VoiceStopTrigger(usage:micUsage,mode:"toggle")
        check(toggleStop.shouldStop(usage:micUsage,down:true,active:true),"second toggle press stops an owned session without route lookup")
        check(!toggleStop.shouldStop(usage:micUsage,down:false,active:true),"toggle release cannot immediately stop first press")
        check(!toggleStop.shouldStop(usage:otherUsage,down:true,active:true),"another button cannot stop the owned session")
        check(!toggleStop.shouldStop(usage:micUsage,down:true,active:false),"idle toggle press remains a start action")
        let holdStop=VoiceStopTrigger(usage:micUsage,mode:"hold")
        check(holdStop.shouldStop(usage:micUsage,down:false,active:true),"hold release cancels active or pending start")
        check(!holdStop.shouldStop(usage:micUsage,down:true,active:true),"repeated hold down does not stop")
        let speed=CursorSpeedSettings(level:0.6875)
        try speed.validate()
        check(speed.fixed == 45056,"cursor native fixed point encoding")
        for invalid in [-0.01,3.01,Double.nan,Double.infinity] {
            do { try CursorSpeedSettings(level:invalid).validate();check(false,"invalid cursor speed accepted") }
            catch { check(true,"invalid cursor speed rejected") }
        }
        let cursorLease=CursorLease(bootSession:"boot-a",registryID:123,vendorID:0x1915,productID:0x1025,original:45056,applied:65536)
        check(cursorLease.shouldRestore(current:65536),"restore only owned cursor setting")
        check(!cursorLease.shouldRestore(current:32768),"preserve external speed change")
        check(cursorLease.belongsTo(boot:"boot-a") && !cursorLease.belongsTo(boot:"boot-b"),"never restore stale registry identity after reboot")
        let legacySpeed=try JSONDecoder().decode(CursorSpeedSettings.self,from:Data(#"{"level":0.5,"enabled":true}"#.utf8))
        check(legacySpeed.linear == nil,"old cursor preferences preserve native acceleration mode")
        let linearSpeed=CursorSpeedSettings(level:0.8,linear:true)
        check(try JSONDecoder().decode(CursorSpeedSettings.self,from:JSONEncoder().encode(linearSpeed))==linearSpeed,"linear cursor preference round trips")
        check(linearSpeed.fixed == -65536,"acceleration bypass uses native negative fixed-point value")
        check(CursorSpeedSettings(level:0.8,linear:false).fixed==52429,"accelerated mode retains chosen curve setting")
        let legacyLease=try JSONDecoder().decode(CursorLease.self,from:Data(#"{"bootSession":"a","registryID":1,"vendorID":1,"productID":2,"original":1,"applied":2}"#.utf8))
        check(legacyLease.shouldRestore(current:2),"old restoration journal remains readable")
        let bypassLease=CursorLease(bootSession:"a",registryID:1,vendorID:1,productID:2,original:45056,applied:-65536)
        check(bypassLease.shouldRestore(current:-65536) && !bypassLease.shouldRestore(current:0),"bypass restores only owned native state")
        check(SingleInstanceLock.isReadOnly(["JustVibe Remote","--render-cursor-preview","/tmp/preview.png"]),"cursor preview does not own live session")
        check(ConnectionState.resolve(inputAllowed:false,shortcutsAllowed:true,interfaces:2,openResult:nil) == .inputPermission, "physical receiver does not imply input authorization")
        check(ConnectionState.resolve(inputAllowed:true,shortcutsAllowed:false,interfaces:2,openResult:nil) == .shortcutPermission, "shortcut permission is diagnosed separately")
        check(ConnectionState.resolve(inputAllowed:true,shortcutsAllowed:true,interfaces:0,openResult:nil) == .receiverMissing, "missing receiver is distinct from denied permission")
        check(ConnectionState.resolve(inputAllowed:true,shortcutsAllowed:true,interfaces:2,openResult:-1) == .openFailed, "native connection errors remain visible")
        check(ConnectionState.resolve(inputAllowed:true,shortcutsAllowed:true,interfaces:2,openResult:0) == .ready, "allowed attached receiver can connect")
        let ownershipDirectory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:ownershipDirectory) }
        let firstOwner=SingleInstanceLock(directory:ownershipDirectory),secondOwner=SingleInstanceLock(directory:ownershipDirectory)
        check(try firstOwner.acquire(), "first app owns the session")
        check(try !secondOwner.acquire(), "duplicate app cannot acquire session")
        check(secondOwner.ownerPID == ProcessInfo.processInfo.processIdentifier, "duplicate can identify original app to activate")
        firstOwner.release()
        check(try secondOwner.acquire(), "restart can acquire session after previous owner exits")
        secondOwner.release()
        check(SingleInstanceLock.isReadOnly(["JustVibe Remote","--connection-diagnostics","/tmp/report.json"]), "connection diagnostics do not own a normal app session")
        check(SingleInstanceLock.isReadOnly(["JustVibe Remote","--render-microphone-preview","/tmp/preview.png"]), "offscreen previews do not own a normal session")
        check(!SingleInstanceLock.isReadOnly(["JustVibe Remote"]), "normal launch always requires session ownership")
        let remoteMic = MicrophonePreference(id:"remote.uid",name:"Remote USB mic",guardDictation:true)
        check(MicrophonePolicy.issue(nil,available:[],defaults:[]) == nil, "legacy dictation is unchanged before microphone setup")
        check(MicrophonePolicy.issue(remoteMic,available:["remote.uid"],defaults:["remote.uid"]) == nil, "selected present default mic passes")
        check(MicrophonePolicy.issue(remoteMic,available:[],defaults:["remote.uid"]) != nil, "disconnected selected mic blocks dictation")
        check(MicrophonePolicy.issue(remoteMic,available:["remote.uid"],defaults:["built.in"]) != nil, "another default mic blocks dictation")
        check(MicrophonePolicy.issue(remoteMic,available:["remote.uid"],defaults:[]) != nil, "unknown system input fails closed")
        check(MicrophonePolicy.issue(remoteMic,available:["remote.uid"],defaults:["remote.uid","other"]) != nil, "different communications input fails closed")
        check(MicrophonePolicy.issue(remoteMic,available:["remote.uid"],defaults:["remote.uid","remote.uid","remote.uid"]) == nil, "all matching Windows roles pass")
        check(MicrophonePolicy.issue(MicrophonePreference(id:"",name:"",guardDictation:true),available:[""],defaults:[""]) != nil, "empty microphone identity cannot pass")
        check(MicrophonePolicy.issue(MicrophonePreference(id:"missing",name:"",guardDictation:false),available:[],defaults:[]) == nil, "user can disable system-input safeguard")
        var clip = PCMPreview(sampleRate:8000)
        clip.append([0,0,0,0]); check(clip.level == 0, "silence has no signal")
        clip.append([-32768]); check(clip.level == 1, "full-scale negative sample is measured safely")
        clip.append([32767]); check(clip.level > 0.99 && clip.level <= 1, "positive peak remains in range")
        var bounded = PCMPreview(sampleRate:8000); bounded.append([Int16](repeating:123,count:50000))
        check(bounded.full && bounded.samples.count == 40000, "local preview is capped at five seconds")
        bounded.append([1,2,3]); check(bounded.samples.count == 40000, "late audio cannot grow a finished clip")
        let wave = clip.wave()
        check(String(data:wave.prefix(4),encoding:.ascii) == "RIFF" && String(data:wave[8..<12],encoding:.ascii) == "WAVE", "preview emits a WAV container")
        check(wave.count == 44 + clip.samples.count * 2 && wave[22] == 1 && wave[34] == 16, "WAV declares correct size, mono channels, and PCM16")
        check(wave[52] == 0 && wave[53] == 128 && wave[54] == 255 && wave[55] == 127, "WAV retains signed PCM samples in little endian")
        var quietPreview=PCMPreview(sampleRate:16000)
        quietPreview.append([Int16](repeating:33,count:1600))
        check(quietPreview.hasSignal && quietPreview.meterPercent > 10, "quiet microphone samples remain visible on the logarithmic meter")
        check(quietPreview.decibels != nil && quietPreview.decibels! < -50, "quiet audio reports its real decibel level")
        var silentPreview=PCMPreview(sampleRate:16000);silentPreview.append([Int16](repeating:0,count:1600))
        check(!silentPreview.hasSignal && silentPreview.meterPercent == 0 && !silentPreview.samples.isEmpty, "received silence is distinct from receiving no frames")
        var peakPreview=PCMPreview(sampleRate:16000);peakPreview.append([-32768])
        check(peakPreview.meterPercent == 100, "full scale input stays within meter bounds")
        var setup = SetupProgress(inputAllowed: false, shortcutsAllowed: false, receiverConnected: false, needsDictation: true, microphoneLinked: false, shortcutConfirmed: false, testConfirmed: false)
        check(setup.step == .inputPermission, "input approval first")
        setup.inputAllowed = true
        check(setup.step == .shortcutPermission, "shortcut approval before connection")
        setup.shortcutsAllowed = true
        check(setup.step == .receiver, "receiver before learning")
        setup.receiverConnected = true
        check(setup.step == .microphone, "physical microphone link required")
        setup.microphoneLinked = true
        check(setup.step == .shortcut, "unverified shortcut requires confirmation")
        setup.shortcutConfirmed = true
        check(setup.step == .test, "confirmed shortcut still needs live test")
        setup.testConfirmed = true
        check(setup.step == .ready, "explicit test confirmation completes setup")
        setup.receiverConnected = false
        check(setup.step == .receiver, "completed setup detects disconnected receiver")
        setup.receiverConnected = true; setup.needsDictation = false; setup.microphoneLinked = false; setup.shortcutConfirmed = false; setup.testConfirmed = false
        check(setup.step == .ready, "non-dictation app skips voice setup")
        check(RemoteSetupStage.welcome.next(voice:true) == .app,"setup starts with welcome before app choices")
        check(RemoteSetupStage.app.next(voice:true) == .permissions,"the app choice precedes permission requests")
        check(RemoteSetupStage.permissions.next(voice:true) == .receiver,"setup requires connection after permissions")
        check(RemoteSetupStage.button.next(voice:false) == .practice,"buttons-only journey skips optional voice")
        check(RemoteSetupStage.button.next(voice:true) == .microphone,"voice journey includes microphone selection")
        check(RemoteSetupStage.practice.previous(voice:false) == .button,"Back follows the buttons-only branch")
        check(RemoteSetupStage.practice.previous(voice:true) == .shortcut,"Back follows the voice branch")
        check(RemoteSetupStage.microphone.milestone == RemoteSetupStage.shortcut.milestone,"voice details remain within the controls milestone")
        let pendingSetup=RemoteSetupCheckpoint(stage:.practice,wantsVoice:false,controlID:"ok")
        check(pendingSetup.resuming(appAvailable:true,inputAllowed:true,shortcutsAllowed:true,connected:false).stage == .receiver,"resuming checks disconnected receivers before practice")
        check(pendingSetup.resuming(appAvailable:true,inputAllowed:false,shortcutsAllowed:true,connected:true).stage == .permissions,"resuming catches revoked permissions")
        check(pendingSetup.resuming(appAvailable:false,inputAllowed:true,shortcutsAllowed:true,connected:true).stage == .app,"resuming catches a missing app plugin")
        check(pendingSetup.resuming(appAvailable:true,inputAllowed:true,shortcutsAllowed:true,connected:true).stage == .practice,"valid progress resumes at the saved stage")
        check(try JSONDecoder().decode(RemoteSetupCheckpoint.self,from:JSONEncoder().encode(pendingSetup)) == pendingSetup,"setup stage and optional-voice choice survive restart")
        var voice = VoiceSession()
        check(voice.desiredState(down: true, mode: "toggle") == true, "toggle starts")
        voice.commit(true, now: 100)
        check(voice.desiredState(down: false, mode: "toggle") == nil, "pulse release does not stop toggle")
        check(voice.desiredState(down: true, mode: "toggle") == false, "second press stops")
        check(!voice.expired(now: 219) && voice.expired(now: 220), "bounded voice session")
        check(voice.desiredState(down: false, mode: "hold") == false, "hold release stops")
        voice.commit(false, now: 220)
        check(!voice.expired(now: 1000), "idle never expires")
        check(Usage(page: 12, code: 0x221).isButton, "consumer button can be learned")
        check(!Usage(page: 1, code: 0x30).isButton, "pointer motion ignored")
        check(!Usage(page: 7, code: 0xE0).isButton, "modifiers not learned")
        check(!Usage(page: 0xFF01, code: 0x14).isButton, "vendor audio/data not guessed")
        check(Usage(page: 12, code: 0x221).hidutilCode == 0x0000_000C_0000_0221, "usage pages remain separate")
        let shortcut = try MacShortcut.parse("ctrl+shift+d")
        check(shortcut.key == 2 && shortcut.flags.contains(.maskControl) && shortcut.flags.contains(.maskShift), "shortcut parser")
        do { _ = try MacShortcut.parse("BAD+D"); fatalError("invalid shortcut accepted") } catch { count += 1 }
        let empty = try MappingLease.parse("RegistryID Key Value\n123 UserKeyMapping (null)")
        check(empty.isEmpty, "empty device mapping")
        for text in [
            "123 UserKeyMapping ({ HIDKeyboardModifierMappingSrc = 10; HIDKeyboardModifierMappingDst = 20; })",
            "123 UserKeyMapping ({ HIDKeyboardModifierMappingDst = 20; HIDKeyboardModifierMappingSrc = 10; })"
        ] { check(try MappingLease.parse(text) == [.init(source: 10, destination: 20)], "mapping property order") }
        do { _ = try MappingLease.parse("123 UserKeyMapping (null)\n124 UserKeyMapping (null)"); fatalError("ambiguous mapping accepted") } catch { count += 1 }
        do { _ = try MappingLease.parse("123 UserKeyMapping ({ HIDKeyboardModifierMappingSrc = 10; })"); fatalError("partial mapping accepted") } catch { count += 1 }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let deviceBytes = try Data(contentsOf: root.appendingPathComponent("plugins/bundled/org.justviberemote.device.xingwei-usb/plugin.json"))
        let devicePlugin = try PluginManifest.decode(deviceBytes)
        var defaults = Configuration(); defaults.profile = devicePlugin.device!.profile; defaults.shortcut = "CTRL+SHIFT+D"
        let visual = devicePlugin.device!.layout!
        check(visual.buttons.count == 18, "photo layout includes all visible front-face controls")
        check(visual.buttons.allSatisfy { $0.usage == nil }, "photo geometry does not invent HID signals")
        check(visual.buttons.first(where: {$0.id == "top-right"})?.hint != nil, "unclear photo symbol is documented")
        var learned = Binding(name: "Old microphone label", usage: Usage(page: 12, code: 0x221), action: .dictate, controlID: "microphone")
        var migrated = try visual.bindings(preserving: [learned])
        check(migrated.first?.usage == learned.usage && migrated.first?.name == "Microphone", "stable ID survives label changes")
        let legacy = Binding(name: "Spare old control", usage: Usage(page: 7, code: 0x3D), action: .escape)
        migrated = try visual.bindings(preserving: [learned, legacy])
        check(migrated.contains(legacy), "unmatched legacy bindings remain accessible")
        learned.controlID = nil; learned.name = "Microphone"
        check(try visual.bindings(preserving: [learned]).first?.usage == learned.usage, "legacy names migrate to stable IDs")
        let crowded = (0..<64).map { Binding(name:"Legacy \($0)",action:.native) }
        do { _ = try visual.bindings(preserving:crowded);fatalError("overflow silently dropped old controls") } catch { count += 1 }
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        var config = try store.load(defaults: defaults)
        check(config.profile.hardwareID == "1915:1025" && !config.shortcutConfirmed, "safe defaults")
        check(!config.autoConnect && !config.dictationTested, "connection and test require consent")
        try store.save(config)
        check(config.microphones.isEmpty, "old settings do not guess an audio input")
        var oldObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        oldObject["pointingCalibrations"] = ["retired-experiment": ["invalidOldData": true]]; oldObject.removeValue(forKey: "remoteSetupCompleted"); oldObject.removeValue(forKey: "remoteSetupCheckpoint"); oldObject.removeValue(forKey: "remotePreferences"); oldObject.removeValue(forKey: "cursorSettings"); oldObject.removeValue(forKey: "microphones"); oldObject.removeValue(forKey: "followActiveApp"); oldObject.removeValue(forKey: "appMappings"); oldObject.removeValue(forKey: "autoConnect"); oldObject.removeValue(forKey: "dictationTested")
        try JSONSerialization.data(withJSONObject: oldObject).write(to: store.url)
        check(try !store.load().autoConnect && !store.load().dictationTested, "old settings retain safe setup defaults")
        check(try !store.load().followActiveApp && store.load().appMappings.isEmpty, "old settings preserve manual routing")
        check(try store.load().cursorSettings.isEmpty,"legacy settings do not enable cursor changes")
        check(try store.load().remotePreferences.isEmpty,"legacy settings do not require remote preference records")
        check(try !store.load().remoteSetupCompleted,"unconfigured legacy settings still receive the new welcome journey")
        var verifiedLegacy=oldObject;verifiedLegacy["dictationTested"]=true
        let verifiedMigration=try JSONDecoder().decode(Configuration.self,from:JSONSerialization.data(withJSONObject:verifiedLegacy))
        check(verifiedMigration.remoteSetupCompleted,"existing verified remotes are not forced through setup again")
        let migratedSettings=try store.load()
        let migratedObject=try JSONSerialization.jsonObject(with:JSONEncoder().encode(migratedSettings)) as! [String:Any]
        check(migratedObject["pointingCalibrations"]==nil,"obsolete calibration data is ignored and omitted without blocking settings migration")
        config.cursorSettings[config.devicePluginID]=speed
        config.cursorSettings["community.other-remote"]=CursorSpeedSettings(level:1.5)
        try store.save(config)
        check(try store.load().cursorSettings[config.devicePluginID]==speed,"cursor speed survives configuration reload")
        check(try store.load().cursorSettings["community.other-remote"]?.level==1.5,"cursor preferences remain separate per device plugin")
        config.microphones[config.devicePluginID] = remoteMic
        try store.save(config)
        check(try store.load().microphones[config.devicePluginID]?.id == remoteMic.id, "selected microphone persists")
        check(try store.load().microphones[config.devicePluginID]?.guardDictation == true, "microphone safeguard preference persists")
        config.autoConnect = true; config.dictationTested = true
        config.bindings[0].usage = Usage(page: 12, code: 0x221)
        try store.save(config)
        check(try store.load().autoConnect && store.load().dictationTested, "setup choices persist")
        check(try store.load().bindings[0].usage == config.bindings[0].usage, "learned button saved")
        config.bindings = try visual.bindings(preserving: config.bindings)
        try store.save(config)
        check(try store.load().bindings.count > 6, "variable visual bindings survive configuration reload")
        try Data("invalid".utf8).write(to: store.url)
        do { _ = try store.load(); fatalError("corrupt configuration accepted") } catch { count += 1 }
        check(try String(contentsOf: store.url, encoding: .utf8) == "invalid", "corrupt configuration preserved")
        struct Case: Decodable { let name: String; let valid: Bool; let manifest: [String: JSONValue] }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: root.appendingPathComponent("plugins/tests/conformance.json")))
        for test in cases {
            let data = try JSONEncoder().encode(test.manifest)
            var valid = true
            do { _ = try PluginManifest.decode(data) } catch { valid = false }
            check(valid == test.valid, "plugin conformance: " + test.name)
        }
        let user = directory.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let bundled = root.appendingPathComponent("plugins/bundled")
        var catalog = PluginCatalog(bundled: bundled, user: user)
        check(catalog.plugins.count == 4 && catalog.diagnostics.isEmpty, "bundled plugins discovered")
        let cursor=try catalog.find("org.justviberemote.app.cursor",kind:"app")
        check(cursor.app?.targets["macos"]?.bundleIds == ["com.todesktop.230313mzl4w4u92"],"bundled Cursor targets the inspected desktop application")
        let cursorConfig=try PluginSelection.select(defaults,catalog:catalog,deviceID:defaults.devicePluginID,appID:cursor.id)
        check(cursorConfig.shortcut == "CTRL+M" && cursorConfig.voiceMode == "toggle" && !cursorConfig.shortcutConfirmed,"Cursor defaults to toggle Control+M and requires confirmation")
        check(cursor.app?.actions["dictate"]?.operation == "toggle-shortcut","Cursor uses separate start and stop taps")
        let antigravity=try catalog.find("org.justviberemote.app.antigravity",kind:"app")
        check(antigravity.name == "Antigravity" && antigravity.app?.targets["macos"]?.bundleIds == ["com.google.antigravity"],"bundled Antigravity targets the inspected desktop application")
        check(antigravity.app?.supports(.focus) == true && antigravity.app?.supports(.send) == true,"Antigravity exposes the existing app-control actions")
        func install(_ folder: String, _ bytes: Data) throws {
            let target = user.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try bytes.write(to: target.appendingPathComponent("plugin.json"))
        }
        try install("override", deviceBytes)
        catalog = PluginCatalog(bundled: bundled, user: user)
        check(catalog.plugins.count == 4 && catalog.diagnostics.count == 1, "bundled identity cannot be overridden")
        let template = try Data(contentsOf: root.appendingPathComponent("plugins/examples/app/plugin.json"))
        try install("first", template); try install("second", template)
        catalog = PluginCatalog(bundled: bundled, user: user)
        check(catalog.plugins.count == 4 && catalog.diagnostics.count == 2, "duplicate user IDs disabled")
        try install("broken", Data("bad json".utf8))
        catalog = PluginCatalog(bundled: bundled, user: user)
        check(catalog.plugins.count == 4 && catalog.diagnostics.count == 3, "malformed plugin isolated")
        try FileManager.default.removeItem(at: user.appendingPathComponent("second"))
        catalog = PluginCatalog(bundled: bundled, user: user)
        check(catalog.plugins.count == 5, "third-party app plugin accepted")
        var selected = defaults
        selected.bindings[0].usage = Usage(page: 12, code: 0x221)
        selected.shortcutConfirmed = true
        selected.targetAppPath = "/test/Codex.app"
        let original = selected
        selected = try PluginSelection.select(selected, catalog: catalog, deviceID: selected.devicePluginID, appID: "com.example.justviberemote.editor")
        check(!selected.shortcutConfirmed && selected.targetAppPath.isEmpty, "new app requires shortcut confirmation and fresh target override")
        check(selected.bindings[0].action == .native, "unsupported intent becomes native")
        selected = try PluginSelection.select(selected, catalog: catalog, deviceID: original.devicePluginID, appID: original.appPluginID)
        check(selected.bindings[0].usage == original.bindings[0].usage, "device/app pair bindings restored")
        check(selected.bindings[0].action == .dictate, "saved app intent restored")
        let editorID = "com.example.justviberemote.editor"
        var perApp = original
        perApp.voiceMode = "hold"; perApp.dictationTested = true
        perApp = try PluginSelection.select(perApp, catalog: catalog, deviceID: perApp.devicePluginID, appID: editorID)
        check(perApp.bindings[0].usage == original.bindings[0].usage, "new app reuses physical button learning")
        perApp.bindings[0].action = .escape
        perApp.targetAppPath = "/Applications/Editor.app"
        perApp = try PluginSelection.select(perApp, catalog: catalog, deviceID: perApp.devicePluginID, appID: original.appPluginID)
        check(perApp.shortcutConfirmed && perApp.targetAppPath == original.targetAppPath && perApp.voiceMode == "hold" && perApp.dictationTested, "returning app restores shortcut, location, voice mode and test")
        check(perApp.bindings[0].action == .dictate, "app actions remain separate")
        perApp.followActiveApp = true
        let codexFront = ForegroundApp(bundleID: "com.openai.codex", name: "Codex", path: original.targetAppPath, instance: "1")
        let editorFront = ForegroundApp(bundleID: "com.example.editor", name: "Example Editor", path: "/Applications/Editor.app", instance: "2")
        let editRoute = AppRouting.resolve(perApp, apps: catalog.apps, foreground: editorFront)
        check(editRoute?.bindings[0].action == .escape && editRoute?.appPluginID == editorID, "foreground editor uses its saved button action")
        check(AppRouting.resolve(perApp, apps: catalog.apps, foreground: codexFront)?.bindings[0].action == .dictate, "foreground Codex uses its different action")
        check(perApp.appPluginID == original.appPluginID && perApp.bindings[0].action == .dictate, "routing does not change the editor profile")
        check(AppRouting.resolve(perApp, apps: catalog.apps, foreground: ForegroundApp(bundleID: "unknown", name: "Other")) == nil, "unknown app keeps native actions")
        check(AppRouting.resolve(perApp, apps: catalog.apps, foreground: nil) == nil, "unreadable foreground keeps native actions")
        check(AppRouting.resolve(perApp, apps: catalog.apps, foreground: ForegroundApp(bundleID:"com.example.editor", name:"Example Editor", path:"/wrong/Editor.app")) == nil, "explicit app path never falls back to plugin names")
        var unconfigured = original; unconfigured.followActiveApp = true
        check(AppRouting.resolve(unconfigured, apps: catalog.apps, foreground: editorFront) == nil, "unconfigured plugins are not activated")
        var isolated = perApp; isolated.devicePluginID = "another.device"
        check(AppRouting.resolve(isolated, apps: catalog.apps, foreground: editorFront) == nil, "another device does not reuse app bindings")
        var manual = perApp; manual.followActiveApp = false
        check(AppRouting.resolve(manual, apps: catalog.apps, foreground: editorFront)?.appPluginID == manual.appPluginID, "manual mode preserves selected target")
        let noSpecific=try PluginSelection.select(perApp,catalog:catalog,deviceID:perApp.devicePluginID,appID:Configuration.noSpecificAppID)
        check(noSpecific.bindings.allSatisfy { $0.action == .native },"no-specific-app selection keeps every original remote action")
        check(noSpecific.targetAppPath.isEmpty && noSpecific.shortcut.isEmpty,"no-specific-app selection has no launch target or voice shortcut")
        check(AppRouting.resolve(noSpecific,apps:catalog.apps,foreground:codexFront)?.appPluginID == perApp.appPluginID,"editing shared controls still routes the active app to its saved profile")
        var manualNative=noSpecific;manualNative.followActiveApp=false
        check(AppRouting.resolve(manualNative,apps:catalog.apps,foreground:codexFront)?.appPluginID == Configuration.noSpecificAppID,"shared profile routes the active app with automatic routing off")
        var sharedEdited=noSpecific;sharedEdited.bindings[0].action = .backspace
        check(AppRouting.resolve(sharedEdited,apps:catalog.apps,foreground:ForegroundApp(bundleID:"unknown",name:"Other"))?.bindings[0].action == .backspace,"shared controls are the fallback for an unrelated foreground app")
        check(AppRouting.resolve(sharedEdited,apps:catalog.apps,foreground:nil) == nil,"shared controls require a foreground app")
        check(!AppRouting.sharedActions.supports(.dictate) && !AppRouting.sharedActions.supports(.focus),"shared controls never guess dictation or launch a target app")
        let sharedToApp=try PluginSelection.select(sharedEdited,catalog:catalog,deviceID:sharedEdited.devicePluginID,appID:perApp.appPluginID)
        let sharedRestored=try PluginSelection.select(sharedToApp,catalog:catalog,deviceID:sharedEdited.devicePluginID,appID:Configuration.noSpecificAppID)
        check(sharedRestored.bindings[0].action == .backspace,"shared mappings survive round trips through an app profile")
        let fallbackFromApp=AppRouting.resolve(sharedToApp,apps:catalog.apps,foreground:ForegroundApp(bundleID:"unknown",name:"Other"))
        check(fallbackFromApp?.appPluginID == Configuration.noSpecificAppID && fallbackFromApp?.bindings[0].action == .backspace,"unknown foreground apps use saved shared controls even while editing an app profile")
        check(fallbackFromApp?.shortcut.isEmpty == true && fallbackFromApp?.shortcutConfirmed == false,"shared fallback never inherits an app-specific dictation shortcut")
        check(AppRouting.resolve(sharedEdited,apps:catalog.apps,foreground:editorFront)?.bindings[0].action == .escape,"saved app actions override shared fallback actions")
        check(sharedEdited.appPluginID == Configuration.noSpecificAppID && sharedEdited.bindings[0].action == .backspace,"automatic routing preserves the displayed shared profile and its mappings")
        let restoredApp=try PluginSelection.select(noSpecific,catalog:catalog,deviceID:perApp.devicePluginID,appID:perApp.appPluginID)
        check(restoredApp.bindings == perApp.bindings && restoredApp.shortcut == perApp.shortcut,"switching back from no-specific-app restores saved controls and voice")
        let reopenedNative=try PluginSelection.selectRemote(noSpecific,catalog:catalog,deviceID:noSpecific.devicePluginID)
        check(reopenedNative.appPluginID == Configuration.noSpecificAppID,"reopening a remote preserves no-specific-app selection")
        let editorPlugin = try catalog.find(editorID, kind:"app")
        let codexPlugin = try catalog.find(original.appPluginID, kind:"app")
        var names = perApp; names.targetAppPath = ""
        var savedEditor = names.appMappings[AppRouting.key(names.devicePluginID, editorID)]!
        savedEditor.targetAppPath = ""; names.appMappings[AppRouting.key(names.devicePluginID, editorID)] = savedEditor
        check(AppRouting.resolve(names, apps:[codexPlugin], foreground:ForegroundApp(bundleID:"com.openai.codex"))?.appPluginID == original.appPluginID, "mac bundle identity matches")
        check(AppRouting.resolve(names, apps:[codexPlugin], foreground:ForegroundApp(name:"Codex")) != nil, "legacy app name fallback matches")
        check(codexPlugin.name == "ChatGPT", "bundled app displays ChatGPT under its canonical plugin ID")
        check(AppRouting.resolve(names, apps:[codexPlugin], foreground:ForegroundApp(name:"ChatGPT"))?.appPluginID == original.appPluginID, "ChatGPT name routes existing saved mappings")
        check(AppRouting.resolve(names, apps:[editorPlugin,editorPlugin], foreground:editorFront) == nil, "equal matches disable custom routing")
        var sharedJSON = try JSONSerialization.jsonObject(with: template) as! [String:Any]
        sharedJSON["id"] = "com.example.justviberemote.other"
        var appJSON = sharedJSON["app"] as! [String:Any]
        appJSON["targets"] = ["macos":["bundleIds":["other.bundle"],"names":["Codex"]],"windows":["bundleIds":[],"names":["Codex"]]]
        sharedJSON["app"] = appJSON
        let overlap = try PluginManifest.decode(JSONSerialization.data(withJSONObject:sharedJSON))
        names.appMappings[AppRouting.key(names.devicePluginID, overlap.id)] = savedEditor
        check(AppRouting.resolve(names, apps:[overlap,codexPlugin], foreground:ForegroundApp(bundleID:"com.openai.codex",name:"Codex"))?.appPluginID == original.appPluginID, "exact bundle identity outranks overlapping name")
        check(AppRouting.resolve(names, apps:[overlap,codexPlugin], foreground:ForegroundApp(name:"Codex")) == nil, "overlapping name requires disambiguation")
        var previousVersion = original
        var legacyButtons = original.bindings; legacyButtons[0].usage = Usage(page:12,code:0x222)
        previousVersion.bindingSets[AppRouting.key(previousVersion.devicePluginID,editorID)] = legacyButtons
        let restoredLegacy = try PluginSelection.select(previousVersion,catalog:catalog,deviceID:previousVersion.devicePluginID,appID:editorID)
        check(restoredLegacy.bindings[0].usage == legacyButtons[0].usage, "existing per-app learning is never overwritten by another profile")
        let reduced = PluginManifest(schemaVersion:editorPlugin.schemaVersion,apiVersion:editorPlugin.apiVersion,id:editorPlugin.id,version:editorPlugin.version,name:editorPlugin.name,author:editorPlugin.author,kind:editorPlugin.kind,platforms:editorPlugin.platforms,capabilities:editorPlugin.capabilities,device:nil,app:AppPlugin(adapter:"shortcuts",targets:editorPlugin.app!.targets,actions:[:]))
        check(AppRouting.resolve(perApp,apps:[reduced],foreground:editorFront)?.bindings[0].action == .native, "removed plugin actions revert to native")
        let roundtrip = try JSONDecoder().decode(Configuration.self,from:JSONEncoder().encode(perApp))
        check(roundtrip.followActiveApp && roundtrip.appMappings[AppRouting.key(perApp.devicePluginID,editorID)]?.bindings[0].action == .escape, "active-app settings persist")
        var legacyConfig = perApp; legacyConfig.appMappings = [:]
        let legacyRoute = AppRouting.resolve(legacyConfig,apps:catalog.apps,foreground:ForegroundApp(bundleID:"com.example.editor",name:"Example Editor"))
        check(legacyRoute?.bindings[0].action == .escape && legacyRoute?.shortcutConfirmed == false, "legacy binding sets migrate without guessing shortcut consent")
        do { _ = try catalog.find("missing.app", kind: "app"); fatalError("missing plugin accepted") } catch { count += 1 }
        do { _ = try PluginManifest.decode(Data(repeating: 32, count: 65_537)); fatalError("large manifest accepted") } catch { count += 1 }
        let voiceOwner=RemoteVoiceOwnership()
        check(voiceOwner.claim("remote-a"),"first remote owns dictation output")
        check(!voiceOwner.claim("remote-b"),"second remote cannot overlap held dictation")
        voiceOwner.release("remote-b")
        check(voiceOwner.owner == "remote-a","disconnecting another remote cannot release the voice owner")
        check(!voiceOwner.allows("remote-b") && voiceOwner.allows("remote-a"),"other remote typing cannot interfere with held shortcuts")
        voiceOwner.release("remote-a")
        check(voiceOwner.claim("remote-b"),"another connected remote can dictate after the owner stops")
        voiceOwner.release("remote-b")
        check(voiceOwner.allows("remote-a") && voiceOwner.allows("remote-b"),"both remotes can send app actions when dictation is idle")
        var secondDeviceJSON = try JSONSerialization.jsonObject(with:deviceBytes) as! [String:Any]
        let secondID="com.example.justviberemote.test-receiver"
        secondDeviceJSON["id"]=secondID;secondDeviceJSON["name"]="Test receiver"
        try install("test-receiver",JSONSerialization.data(withJSONObject:secondDeviceJSON))
        let multiCatalog=PluginCatalog(bundled:bundled,user:user)
        var firstRemote=original
        firstRemote.bindings=try visual.bindings(preserving:firstRemote.bindings)
        firstRemote.followActiveApp=true;firstRemote.suppressOriginal=false;firstRemote.autoConnect=true
        firstRemote.microphones[firstRemote.devicePluginID]=MicrophonePreference(id:"first-mic",name:"First mic",guardDictation:false)
        let firstButtons=firstRemote.bindings
        var secondRemote=try PluginSelection.selectRemote(firstRemote,catalog:multiCatalog,deviceID:secondID)
        check(!secondRemote.remoteSetupCompleted && secondRemote.remoteSetupCheckpoint == nil,"a new remote receives its own fresh setup journey")
        check(secondRemote.devicePluginID == secondID,"opening a different remote selects its own device")
        check(secondRemote.followActiveApp && secondRemote.suppressOriginal && !secondRemote.autoConnect,"a new remote defaults to automatic app routing without inheriting device behavior or auto-connect")
        check(secondRemote.bindings[0].usage == nil,"physical button learning cannot leak to a different receiver")
        secondRemote=try PluginSelection.select(secondRemote,catalog:multiCatalog,deviceID:secondID,appID:editorID)
        secondRemote.bindings[0].usage=Usage(page:7,code:0x45);secondRemote.bindings[0].action = .escape
        secondRemote.followActiveApp=false;secondRemote.suppressOriginal=true
        let secondButtons=secondRemote.bindings
        firstRemote=try PluginSelection.selectRemote(secondRemote,catalog:multiCatalog,deviceID:original.devicePluginID)
        check(firstRemote.appPluginID == original.appPluginID,"returning to a remote restores its own selected app")
        check(firstRemote.bindings == firstButtons,"first remote retains its button mappings")
        check(firstRemote.followActiveApp && !firstRemote.suppressOriginal && firstRemote.autoConnect,"returning restores that remote's routing and device behavior")
        secondRemote=try PluginSelection.selectRemote(firstRemote,catalog:multiCatalog,deviceID:secondID)
        check(secondRemote.appPluginID == editorID && secondRemote.bindings == secondButtons,"second remote restores its independent app and learned buttons")
        check(secondRemote.microphones[original.devicePluginID]?.id == "first-mic","per-remote microphone choices remain intact")
        let remoteRoundtrip=try JSONDecoder().decode(Configuration.self,from:JSONEncoder().encode(secondRemote))
        check(remoteRoundtrip.remotePreferences[original.devicePluginID]?.selectedAppID == original.appPluginID,"remote selections survive saved-settings round trip")
        let firstStore=ConfigurationStore(url:directory.appendingPathComponent("remote-a/settings.json"))
        let secondStore=ConfigurationStore(url:directory.appendingPathComponent("remote-b/settings.json"))
        try firstStore.save(firstRemote);try secondStore.save(secondRemote)
        var changedSecond=secondRemote;changedSecond.bindings[0].action = .native;try secondStore.save(changedSecond)
        check(try firstStore.load().bindings == firstButtons,"saving a second active remote never overwrites the first remote's file")
        print("JustVibe Remote macOS: \(count) checks passed")
    }
}

// Preserve arbitrary fixture JSON without involving a third-party test library.
private enum JSONValue: Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Int), bool(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let result = try? value.decode(Bool.self) { self = .bool(result) }
        else if let result = try? value.decode(Int.self) { self = .number(result) }
        else if let result = try? value.decode(String.self) { self = .string(result) }
        else if let result = try? value.decode([JSONValue].self) { self = .array(result) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let result): try value.encode(result)
        case .array(let result): try value.encode(result)
        case .string(let result): try value.encode(result)
        case .number(let result): try value.encode(result)
        case .bool(let result): try value.encode(result)
        case .null: try value.encodeNil()
        }
    }
}

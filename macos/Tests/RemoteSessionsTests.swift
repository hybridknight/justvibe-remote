import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Integration checks use temporary settings and fixture plugins. No receiver
/// session is started, no shortcuts are sent, and no microphone is opened.
@main struct RemoteSessionsTests {
    static func main() throws {
        var count=0
        func check(_ condition:Bool,_ message:String) {
            precondition(condition,"FAIL: " + message);count += 1
        }
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("remote-sessions-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let bundled=directory.appendingPathComponent("bundled")
        try FileManager.default.copyItem(at:source.appendingPathComponent("plugins/bundled"),to:bundled)
        let fixtureURL=bundled.appendingPathComponent("org.justviberemote.device.xingwei-usb/plugin.json")
        let firstID="org.justviberemote.device.xingwei-usb",secondID="com.example.justviberemote.session-test"
        var fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:fixtureURL)) as! [String:Any]
        fixture["id"]=secondID;fixture["name"]="Session test receiver"
        var device=fixture["device"] as! [String:Any],profile=device["profile"] as! [String:Any]
        profile["productId"]=4134;profile["id"]="test-receiver-2";device["profile"]=profile;fixture["device"]=device
        let secondFolder=bundled.appendingPathComponent(secondID);try FileManager.default.createDirectory(at:secondFolder,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:fixture).write(to:secondFolder.appendingPathComponent("plugin.json"))
        let legacyStore=ConfigurationStore(url:directory.appendingPathComponent("settings.json"))
        let catalog=PluginCatalog(bundled:bundled,user:directory.appendingPathComponent("plugins"))
        var legacy=Configuration();legacy.profile=try catalog.find(firstID,kind:"device").device!.profile
        legacy.shortcut="CTRL+SHIFT+D";legacy.shortcutConfirmed=true
        legacy.bindings=try catalog.find(firstID,kind:"device").device!.layout!.bindings()
        legacy.bindings[0].usage=Usage(page:12,code:0x221)
        try legacyStore.save(legacy)
        let originalBytes=try Data(contentsOf:legacyStore.url)
        let workspace=try RemoteSessions(store:legacyStore,bundledPlugins:bundled)
        check(workspace.controllers.count == 2,"both receiver sessions exist at once")
        let first=workspace.controllers[firstID]!,second=workspace.controllers[secondID]!
        check(first !== second,"receivers have independent live controllers")
        let antigravityConfig=try PluginSelection.select(first.config,catalog:workspace.catalog,deviceID:firstID,appID:"org.justviberemote.app.antigravity")
        check(antigravityConfig.shortcut == "CTRL+M" && antigravityConfig.voiceMode == "toggle","Antigravity profile defaults to Control+M and press-once voice activation")
        check(antigravityConfig.bindings.first(where:{$0.controlID == "microphone"})?.action == .dictate,"Antigravity profile connects the microphone button to dictation")
        check(antigravityConfig.bindings.first(where:{$0.controlID == "microphone"})?.usage == legacy.bindings.first(where:{$0.controlID == "microphone"})?.usage,"Antigravity reuses this receiver's learned microphone signal")
        check(!antigravityConfig.shortcutConfirmed,"new voice profiles retain explicit shortcut confirmation")
        check(try workspace.catalog.find("org.justviberemote.app.antigravity",kind:"app").app?.actions["dictate"]?.operation == "toggle-shortcut","Antigravity declares toggle semantics instead of a held key")
        check(first.config.bindings[0].usage == legacy.bindings[0].usage,"legacy learned button migrates to its remote")
        check(second.config.bindings[0].usage == nil,"second receiver never inherits physical learning")
        check(!first.running && !second.running,"constructing a workspace never opens receivers")
        check(first.store.url != second.store.url,"each remote has its own settings file")
        var next=first.config;next.bindings[0].action = .escape;try first.update(next)
        check(second.config.bindings[0].action != .escape,"saving one controller leaves the other untouched")
        var other=second.config;other.bindings[0].action = .native;other.voiceMode="hold";try second.update(other)
        check(first.config.bindings[0].action == .escape && first.config.voiceMode != "hold","second receiver changes cannot alter the first receiver")
        check(first.claimVoice?() == true,"first remote can own the shared voice channel")
        check(second.claimVoice?() == false,"second remote cannot overlap a held voice shortcut")
        let checkpoint=RemoteSetupCheckpoint(stage:.button,wantsVoice:false,controlID:"ok")
        try first.saveSetupCheckpoint(checkpoint)
        check(first.config.remoteSetupCheckpoint == checkpoint,"onboarding progress saves within its remote")
        check(second.config.remoteSetupCheckpoint == nil,"one remote's setup progress never advances another")
        check(second.claimVoice?() == false,"saving presentation progress does not restart or release a live shortcut owner")
        check(!first.config.remoteSetupCompleted,"saving a checkpoint never reports setup completed")
        try second.stop()
        check(second.claimVoice?() == false,"stopping a different session cannot release the owner")
        try first.stop()
        check(second.claimVoice?() == true,"stopping the owning session frees the voice channel")
        second.releaseVoice?()
        let loaded=try RemoteSessions(store:legacyStore,bundledPlugins:bundled)
        check(loaded.controllers[firstID]?.config.remoteSetupCheckpoint == checkpoint,"continued setup resumes after restarting the workspace")
        check(loaded.controllers[firstID]?.config.bindings[0].action == .escape,"first receiver settings survive workspace restart")
        check(loaded.controllers[secondID]?.config.voiceMode == "hold","second receiver settings survive workspace restart")
        check(try Data(contentsOf:legacyStore.url) == originalBytes,"migration preserves the original settings file")
        check(try legacyStore.loadCurrentRemote().bindings[0].action == .escape,"existing diagnostics read the migrated current-remote settings")
        let context=CGContext(data:nil,width:1600,height:900,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.3,green:0.3,blue:0.8,alpha:1));context.fill(CGRect(x:0,y:0,width:1600,height:900))
        let sourceImage=directory.appendingPathComponent("user-reference.png")
        let encoder=CGImageDestinationCreateWithURL(sourceImage as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(encoder,context.makeImage()!,nil);check(CGImageDestinationFinalize(encoder),"artwork test fixture is a valid image")
        let originalImage=try Data(contentsOf:sourceImage),buttonsBeforeArtwork=first.config.bindings
        try first.setArtwork(from:sourceImage)
        check(first.artwork.image != nil && second.artwork.image == nil,"reference artwork stays with its own remote")
        let normalized=try Data(contentsOf:first.artwork.url)
        let decoded=CGImageSourceCreateWithData(normalized as CFData,nil)!
        let dimensions=CGImageSourceCopyPropertiesAtIndex(decoded,0,nil) as! [CFString:Any]
        check((dimensions[kCGImagePropertyPixelWidth] as! NSNumber).intValue<=1024,"uploaded references are bounded for display")
        check(try Data(contentsOf:sourceImage) == originalImage,"importing artwork never changes the user's original image")
        check(first.config.bindings == buttonsBeforeArtwork,"reference artwork never changes learned buttons")
        let artworkRestored=RemoteArtworkStore(directory:first.store.url.deletingLastPathComponent())
        check(artworkRestored.image != nil,"reference artwork survives reopening the remote")
        let invalidImage=directory.appendingPathComponent("invalid-image.png");try Data("not an image".utf8).write(to:invalidImage)
        do { try first.setArtwork(from:invalidImage);check(false,"invalid image was accepted") } catch { check(true,"invalid reference images are rejected") }
        check(try Data(contentsOf:first.artwork.url) == normalized,"failed imports preserve existing artwork")
        try first.resetArtwork()
        check(first.artwork.image == nil && !FileManager.default.fileExists(atPath:first.artwork.url.path),"reset returns to the generic illustration")
        let appFolder=directory.appendingPathComponent("Example Editor.app")
        try FileManager.default.createDirectory(at:appFolder.appendingPathComponent("Contents"),withIntermediateDirectories:true)
        let info:[String:String]=["CFBundleIdentifier":"com.example.local-editor","CFBundleName":"Example Editor","CFBundlePackageType":"APPL","CFBundleExecutable":"ExampleEditor"]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:appFolder.appendingPathComponent("Contents/Info.plist"))
        let application=try LocalAppRegistration(url:appFolder)
        check(application.name == "Example Editor" && application.bundleID == "com.example.local-editor","dropped apps use inspected bundle metadata")
        do { _ = try LocalAppRegistration(url:sourceImage);check(false,"image accepted as app") } catch { check(true,"non-app drops are rejected") }
        let appCount=workspace.catalog.apps.count
        let secondBefore=try Data(contentsOf:second.store.url)
        check(second.claimVoice?() == true,"another receiver owns voice during app registration")
        do { _ = try workspace.addApp(application,dictationShortcut:"not+a+valid+key");check(false,"invalid voice shortcut accepted") } catch { check(true,"invalid shortcuts fail before installing a profile") }
        check(workspace.catalog.apps.count == appCount,"failed app registration leaves catalog unchanged")
        let local=try workspace.addApp(application)
        check(local.platforms == ["macos"] && local.app?.targets["macos"]?.bundleIds == [application.bundleID],"local profile targets the dropped Mac app exactly")
        check(local.app?.supports(.dictate) == false,"adding an app does not invent dictation support")
        check(local.app?.supports(.focus) == true && local.app?.supports(.send) == true,"local app provides basic assignable controls")
        check(workspace.catalog.apps.count == appCount+1 && second.catalog.apps.contains(where:{$0.id == local.id}),"new app is available across remote editors without reload")
        check(first.claimVoice?() == false,"adding an app never releases another receiver's voice ownership")
        check(try Data(contentsOf:second.store.url) == secondBefore,"registration never rewrites another remote's settings")
        let duplicate=try workspace.addApp(application)
        check(duplicate.id == local.id && workspace.catalog.apps.count == appCount+1,"dropping an existing app reuses its profile")
        let reloadedCatalog=PluginCatalog(bundled:bundled,user:workspace.pluginDirectory)
        check(reloadedCatalog.apps.contains(where:{$0.id == local.id}),"user-added apps survive catalog reload")
        let selected=try LocalAppRegistration.selecting(local,url:application.url,config:first.config,catalog:first.catalog)
        check(selected.targetAppPath == application.url.path && selected.appPluginID == local.id,"drop selects the app and its exact path in one configuration")
        check(selected.bindings.allSatisfy({$0.action == .native}),"new local profiles keep physical buttons native until configured")
        var edited=selected;edited.bindings[0].action = .escape
        let repeated=try LocalAppRegistration.selecting(local,url:application.url,config:edited,catalog:first.catalog)
        check(repeated.bindings[0].action == .escape,"dropping the selected app preserves its customized actions")
        let withVoice=try application.manifest(dictationShortcut:"CTRL+SHIFT+D")
        check(withVoice.app?.supports(.dictate) == true && withVoice.app?.actions["dictate"]?.shortcuts?["macos"] == "CTRL+SHIFT+D","dictation is available only with an explicitly supplied held shortcut")
        do { try LocalAppRegistration.install(local,in:workspace.pluginDirectory);check(false,"existing plugin overwritten") } catch { check(true,"installation cannot replace an existing package") }
        second.releaseVoice?()
        let previousAppID=first.config.appPluginID,previousBindings=first.config.bindings
        try first.selectPlugins(deviceID:firstID,appID:Configuration.noSpecificAppID)
        check(first.availableActions == [.native,.send,.backspace,.escape] && first.appPlugin == nil,"shared selection exposes generic typing controls without a target app")
        var sharedConfig=first.config;sharedConfig.bindings[0].action = .escape
        try first.update(sharedConfig)
        let nativeWorkspace=try RemoteSessions(store:legacyStore,bundledPlugins:bundled)
        check(nativeWorkspace.controllers[firstID]?.config.appPluginID == Configuration.noSpecificAppID,"shared selection survives saving and reopening the workspace")
        check(nativeWorkspace.controllers[firstID]?.config.bindings[0].action == .escape,"shared button mappings survive restarting the workspace")
        try first.selectPlugins(deviceID:firstID,appID:previousAppID)
        check(first.config.bindings == previousBindings,"controller restores app controls after native selection")
        try nativeWorkspace.shutdown()
        let observed=RemoteInterfaceEvidence(name:"Observed receiver",vendorID:0x1915,productID:0x1025,transport:"USB",usagePage:12,usage:1,reportDescriptorHex:"050C0901",descriptorTruncated:false,manufacturer:"  Receiver Maker  ")
        let keyboard=RemoteInterfaceEvidence(name:"Observed receiver",vendorID:0x1915,productID:0x1025,transport:"USB",usagePage:1,usage:6,reportDescriptorHex:nil,descriptorTruncated:false)
        let internalDevice=RemoteInterfaceEvidence(name:"Internal keyboard",vendorID:1452,productID:1,transport:"SPI",usagePage:1,usage:6,reportDescriptorHex:nil,descriptorTruncated:false)
        let bluetooth=RemoteInterfaceEvidence(name:"Bluetooth remote",vendorID:123,productID:456,transport:"Bluetooth Low Energy",usagePage:12,usage:1,reportDescriptorHex:nil,descriptorTruncated:false)
        let invalid=RemoteInterfaceEvidence(name:"Unknown IDs",vendorID:0,productID:0,transport:"USB",usagePage:1,usage:6,reportDescriptorHex:nil,descriptorTruncated:false)
        let discoveries=RemoteDiscovery.grouped([observed,observed,keyboard,internalDevice,bluetooth,invalid])
        check(discoveries.count == 2,"discovery groups external input interfaces and excludes internal or invalid identities")
        let receiver=discoveries.first(where:{$0.vendorID == 0x1915})!
        check(receiver.interfaces.count == 2 && receiver.hardwareID == "1915:1025","duplicate interfaces do not create duplicate receiver rows")
        check(receiver.manufacturer == "Receiver Maker","reported manufacturer is preserved across grouped interfaces and trimmed")
        check(discoveries.first(where:{$0.vendorID == 123})!.manufacturer == nil,"missing manufacturer remains unknown")
        var blankManufacturer=keyboard;blankManufacturer.manufacturer="  \n "
        check(DiscoveredRemote(interfaces:[blankManufacturer]).manufacturer == nil,"blank manufacturer is treated as missing")
        check(receiver.matchingPlugins(in:catalog).map(\.id) == [firstID],"only exact observed hardware IDs match installed support")
        check(discoveries.first(where:{$0.vendorID == 123})!.matchingPlugins(in:catalog).isEmpty,"unrecognized devices do not acquire support from names")
        let prompt=RemoteSetupPrompt.make(device:receiver)
        check(prompt.contains("050C0901") && prompt.contains("Observed receiver"),"prompt carries the selected device's observed descriptor and name")
        check(prompt.contains("Receiver Maker"),"selected device prompt includes its reported manufacturer")
        check(!prompt.contains("Bluetooth remote") && !prompt.contains("Internal keyboard"),"prompt does not export other connected input devices")
        check(prompt.contains("plugins/examples/device") && prompt.contains("Contents/Resources/PluginAuthoring"),"prompt guides discovery in source checkouts and installed apps")
        check(prompt.contains("Show starter files…") && prompt.contains("locate JustVibe Remote's user plugin folder"),"prompt explains resource sharing and installation destination discovery")
        check(!prompt.contains(directory.path) && !prompt.contains(workspace.pluginDirectory.path) && !prompt.contains("/Users/") && !prompt.contains("/Applications/"),"prompt contains no generated absolute paths")
        check(prompt.contains("Do not invent missing hardware facts") && prompt.contains("do not claim Windows support"),"prompt separates observations from support claims")
        check(prompt.contains("host source") && prompt.contains("unchanged") && prompt.contains("official validation pending"),"agent instructions retain host and validator boundaries")
        let unidentified=RemoteSetupPrompt.make(device:nil)
        check(unidentified.contains("BEGIN DEVICE EVIDENCE\nnull\nEND DEVICE EVIDENCE"),"missing-receiver prompt contains no invented hardware identity")
        check(!unidentified.contains(directory.path) && !unidentified.contains(workspace.pluginDirectory.path) && !unidentified.contains("/Users/") && !unidentified.contains("/Applications/"),"identification prompt also contains no generated absolute paths")
        check(unidentified.hasPrefix("Help me find my remote"),"missing receiver prompt starts with identification instead of plugin creation")
        check(unidentified.contains("compare device lists") && unidentified.contains("Only help create a plugin if support is missing"),"agent checks receiver identity and existing support before authoring")
        for setupPrompt in [prompt,unidentified] {
            check(setupPrompt.contains("If I have no photo") && setupPrompt.contains("search online for reference photos") && setupPrompt.contains("source link"),"both prompt paths offer sourced online reference photos when no photo is available")
            check(setupPrompt.contains("Wait for my explicit confirmation") && setupPrompt.contains("leave the appearance unverified"),"online photos require user confirmation before use and unmatched appearances remain unverified")
        }
        check(SingleInstanceLock.isReadOnly(["JustVibe Remote","--render-add-remote-preview","/tmp/preview.png"]),"new remote flow preview never activates hardware sessions")
        let recorded=ShortcutCapture.encode(keyCode:2,modifiers:[.control,.shift])
        check(recorded == "CTRL+SHIFT+D","shortcut recorder encodes a physical modifier chord")
        check(ShortcutCapture.encode(keyCode:2,modifiers:[.command]) == "CMD+D","command chords are recorded without typing command names")
        check(ShortcutCapture.encode(keyCode:49,modifiers:[.option]) == "OPTION+SPACE","space shortcuts use supported output tokens")
        check(ShortcutCapture.encode(keyCode:36,modifiers:[.control]) == "CTRL+RETURN","return is recorded with its canonical token")
        check(ShortcutCapture.encode(keyCode:51,modifiers:[]) == "BACKSPACE","delete key records as Backspace")
        check(ShortcutCapture.encode(keyCode:53,modifiers:[.command]) == "CMD+ESC","modified Escape remains recordable")
        check(ShortcutCapture.encode(keyCode:122,modifiers:[]) == nil,"unsupported function keys are rejected instead of stored")
        check(ShortcutCapture.encode(keyCode:2,modifiers:[.function]) == nil,"Fn is not silently discarded from a recorded shortcut")
        check(ShortcutCapture.encode(keyCode:2,modifiers:[.capsLock,.control]) == "CTRL+D","Caps Lock does not become an unsupported shortcut modifier")
        check(ShortcutCapture.display("CTRL+SHIFT+D") == "⌃ ⇧ D","recorded shortcuts display familiar Mac symbols")
        let replay=try MacShortcut.parse(recorded!)
        check(replay.key == 2 && replay.flags.contains(.maskControl) && replay.flags.contains(.maskShift),"recorded chords round-trip through actual shortcut output parsing")
        let recordedPlugin=try application.manifest(dictationShortcut:recorded)
        check(recordedPlugin.app?.actions["dictate"]?.shortcuts?["macos"] == recorded,"recorded values persist through the app-plugin contract")
        let legacyAppID="org.justviberemote.app.codex",currentAppID="org.justviberemote.app.chatgpt"
        let oldPair=firstID+"|"+legacyAppID,newPair=firstID+"|"+currentAppID
        var oldNamespace=legacy
        oldNamespace.appPluginID=legacyAppID
        oldNamespace.bindingSets=[oldPair:legacy.bindings]
        oldNamespace.appMappings=[oldPair:AppMapping(legacy)]
        oldNamespace.remotePreferences=[firstID:RemotePreferences(oldNamespace)]
        let oldNamespaceData=try JSONEncoder().encode(oldNamespace)
        let namespaceStore=ConfigurationStore(url:directory.appendingPathComponent("legacy-namespace.json"))
        try oldNamespaceData.write(to:namespaceStore.url)
        let migrated=try namespaceStore.load()
        check(migrated.appPluginID == currentAppID,"old selected app namespace migrates to ChatGPT")
        check(migrated.bindingSets[newPair] == legacy.bindings && migrated.bindingSets[oldPair] == nil,"learned binding-set keys migrate without duplicates")
        check(migrated.appMappings[newPair]?.shortcut == legacy.shortcut && migrated.appMappings[oldPair] == nil,"per-app voice mappings migrate with their keys")
        check(migrated.remotePreferences[firstID]?.selectedAppID == currentAppID,"per-remote app selections migrate")
        check(try Data(contentsOf:namespaceStore.url) == oldNamespaceData,"loading legacy namespaces never rewrites the original settings file")
        var conflict=oldNamespace
        var newerBindings=legacy.bindings;newerBindings[0].action = .escape
        conflict.bindingSets[newPair]=newerBindings
        var newerMapping=AppMapping(legacy);newerMapping.shortcut="CMD+D";newerMapping.bindings=newerBindings;conflict.appMappings[newPair]=newerMapping
        let resolved=try JSONDecoder().decode(Configuration.self,from:JSONEncoder().encode(conflict))
        check(resolved.bindingSets[newPair] == newerBindings && resolved.appMappings[newPair]?.shortcut == "CMD+D" && resolved.bindings == newerBindings && resolved.shortcut == "CMD+D","existing ChatGPT settings win namespace collisions, including the active profile")
        try namespaceStore.save(migrated)
        check(!String(data:try Data(contentsOf:namespaceStore.url),encoding:.utf8)!.contains(legacyAppID),"the next save uses only canonical plugin namespaces")
        check(ButtonTestState.shouldEnable(buttonsPageVisible:true,appActive:true,windowVisible:true,windowMiniaturized:false),"focused Buttons page enables test capture")
        check(!ButtonTestState.shouldEnable(buttonsPageVisible:true,appActive:false,windowVisible:true,windowMiniaturized:false),"switching to a target app releases test capture even with Buttons still open")
        check(!ButtonTestState.shouldEnable(buttonsPageVisible:false,appActive:true,windowVisible:true,windowMiniaturized:false),"other JustVibe Remote pages never enable test capture")
        check(!ButtonTestState.shouldEnable(buttonsPageVisible:true,appActive:true,windowVisible:false,windowMiniaturized:false),"hiding the editor restores normal remote actions")
        check(!ButtonTestState.shouldEnable(buttonsPageVisible:true,appActive:true,windowVisible:true,windowMiniaturized:true),"minimizing the editor restores normal remote actions")
        var voiceRouting=try PluginSelection.select(first.config,catalog:workspace.catalog,deviceID:firstID,appID:"org.justviberemote.app.chatgpt")
        voiceRouting.followActiveApp=true;voiceRouting.shortcut="CTRL+SHIFT+D";voiceRouting.shortcutConfirmed=true;voiceRouting.targetAppPath=""
        if let mic=voiceRouting.bindings.firstIndex(where:{$0.controlID == "microphone"}) {
            voiceRouting.bindings[mic].usage=Usage(page:12,code:0xCF);voiceRouting.bindings[mic].action = .dictate
        }
        voiceRouting=try PluginSelection.select(voiceRouting,catalog:workspace.catalog,deviceID:firstID,appID:"org.justviberemote.app.antigravity")
        voiceRouting.shortcutConfirmed=true;voiceRouting.targetAppPath=""
        voiceRouting=try PluginSelection.select(voiceRouting,catalog:workspace.catalog,deviceID:firstID,appID:"org.justviberemote.app.chatgpt")
        let chatRoute=AppRouting.resolve(voiceRouting,apps:workspace.catalog.apps,foreground:ForegroundApp(bundleID:"com.openai.codex",name:"ChatGPT",path:"/Applications/ChatGPT.app",instance:"chat"))
        let antiRoute=AppRouting.resolve(voiceRouting,apps:workspace.catalog.apps,foreground:ForegroundApp(bundleID:"com.google.antigravity",name:"Antigravity",path:"/Applications/Antigravity.app",instance:"anti"))
        check(chatRoute?.bindings.first(where:{$0.usage == Usage(page:12,code:0xCF)})?.action == .dictate,"foreground ChatGPT receives the saved microphone dictation action")
        check(antiRoute?.bindings.first(where:{$0.usage == Usage(page:12,code:0xCF)})?.action == .dictate,"foreground Antigravity receives its own saved microphone dictation action")
        check(chatRoute?.shortcut == "CTRL+SHIFT+D" && chatRoute?.shortcutConfirmed == true,"ChatGPT routing retains its own confirmed shortcut")
        check(antiRoute?.shortcut == "CTRL+M" && antiRoute?.shortcutConfirmed == true,"Antigravity routing retains its confirmed toggle shortcut")
        let sharedEditor=try PluginSelection.select(voiceRouting,catalog:workspace.catalog,deviceID:firstID,appID:Configuration.noSpecificAppID)
        let sharedChatRoute=AppRouting.resolve(sharedEditor,apps:workspace.catalog.apps,foreground:ForegroundApp(bundleID:"com.openai.codex",name:"ChatGPT",path:"/Applications/ChatGPT.app",instance:"chat"))
        let sharedAntiRoute=AppRouting.resolve(sharedEditor,apps:workspace.catalog.apps,foreground:ForegroundApp(bundleID:"com.google.antigravity",name:"Antigravity",path:"/Applications/Antigravity.app",instance:"anti"))
        check(sharedChatRoute?.shortcut == "CTRL+SHIFT+D" && sharedChatRoute?.bindings.first(where:{$0.controlID == "microphone"})?.action == .dictate,"ChatGPT mic dictation automatically works while shared controls are selected in the editor")
        check(sharedAntiRoute?.shortcut == "CTRL+M" && sharedAntiRoute?.bindings.first(where:{$0.controlID == "microphone"})?.action == .dictate,"Antigravity mic dictation automatically works while shared controls are selected in the editor")
        check(sharedEditor.appPluginID == Configuration.noSpecificAppID && sharedEditor.shortcut.isEmpty,"detecting target apps does not overwrite shared editor settings")
        check(AppRouting.resolve(sharedEditor,apps:workspace.catalog.apps,foreground:ForegroundApp(bundleID:"other",name:"Other"))?.appPluginID == Configuration.noSpecificAppID,"switching from dictation apps to another app uses shared controls")
        var testState=ButtonTestState()
        let tested=Usage(page:12,code:0xCF),another=Usage(page:7,code:40)
        testState.observe(tested,down:true,now:10)
        check(testState.lastUsage == nil,"normal input does not record test feedback")
        testState.setEnabled(true)
        testState.observe(tested,down:true,now:10)
        testState.observe(tested,down:false,now:10.05)
        check(testState.lastUsage == tested,"test mode records the physical button signal")
        check(testState.highlights(active:[],now:10.2).contains(tested),"quick button presses remain visible after release")
        check(!testState.highlights(active:[],now:10.5).contains(tested),"released test highlights expire")
        check(testState.highlights(active:[tested],now:20).contains(tested),"held remote buttons stay highlighted")
        testState.observe(another,down:true,now:20)
        check(testState.highlights(active:[tested],now:20.1) == [tested,another],"simultaneous test presses highlight independently")
        testState.setEnabled(false)
        check(testState.lastUsage == nil && testState.highlights(active:[],now:20.1).isEmpty,"leaving test mode clears transient feedback")
        enum CaptureFailure:Error { case exclusive,normal }
        var captureAttempts:[Bool]=[]
        let captureFailure=try ButtonTestCapture.transition(enabled:true) { exclusive in
            captureAttempts.append(exclusive)
            if exclusive { throw CaptureFailure.exclusive }
        }
        check(captureFailure != nil && captureAttempts == [true,false],"exclusive test rejection restores normal capture and reports testing unavailable")
        captureAttempts=[]
        check(try ButtonTestCapture.transition(enabled:true) { captureAttempts.append($0) } == nil,"successful exclusive capture enables testing")
        check(captureAttempts == [true],"successful test capture does not reopen normal input")
        captureAttempts=[]
        do {
            _=try ButtonTestCapture.transition(enabled:true) { exclusive in captureAttempts.append(exclusive);throw CaptureFailure.normal }
            check(false,"failed recovery must not claim a connected session")
        } catch { check(captureAttempts == [true,false],"normal recovery failure is propagated for safe shutdown") }
        captureAttempts=[]
        do {
            _=try ButtonTestCapture.transition(enabled:false) { exclusive in captureAttempts.append(exclusive);throw CaptureFailure.normal }
            check(false,"failed normal capture must propagate")
        } catch { check(captureAttempts == [false],"leaving test mode never retries exclusive capture") }
        let savedBeforeTest=try Data(contentsOf:first.store.url)
        first.setButtonTestMode(true)
        check(first.buttonTestMode && !second.buttonTestMode,"test mode applies only to the selected remote")
        check(!first.running,"opening test mode never connects hardware without user action")
        first.testVoice()
        check(!first.voiceActive && first.status.contains("Leave the Buttons page"),"test mode blocks the dictation test command")
        first.setButtonTestMode(false)
        check(!first.buttonTestMode,"leaving the Buttons page restores normal controller mode")
        check(try Data(contentsOf:first.store.url) == savedBeforeTest,"test mode never writes temporary state into saved mappings")
        try workspace.shutdown();try loaded.shutdown()
        print("JustVibe Remote remote sessions: \(count) checks passed")
    }
}

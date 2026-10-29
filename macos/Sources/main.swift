import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: RemoteController!
    private var sessions: RemoteSessions!
    private var sessionOwner: SingleInstanceLock?
    private var connectionWindow: ConnectionCheck?
    private var setupWizard: QuickSetup?
    private var microphoneWindow: MicrophoneTest?
    private var cursorWindow: CursorSetup?
    private var addRemoteFlow:AddRemoteFlow?
    private let voiceMicrophoneHost=NSStackView()
    private var voiceMicrophonePanel:VoiceMicrophonePanel?
    private weak var voiceMicrophoneController:RemoteController?
    private var voiceTestClosing=false
    private var window: NSWindow!
    private let canvas = RemoteCanvas()
    private var mappingBoard:RemoteMappingBoard!
    private let dictationBinding=NSTextField(labelWithString: "")
    private let dictationBindingHelp=NSTextField(wrappingLabelWithString: "")
    private let appIconSelector = AppIconSelector(frame:.zero)
    private let supportedAppList = NSStackView()
    private var supportedAppSignature = ""
    private let followApp = NSButton(checkboxWithTitle: "Follow active app", target: nil, action: nil)
    private let routeLabel = NSTextField(labelWithString: "")
    private let bindingPicker = NSPopUpButton()
    private let actionPicker = NSPopUpButton()
    private let linked = NSTextField(labelWithString: "Not linked yet")
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let actionHelp = NSTextField(wrappingLabelWithString: "")
    private let learningHelp = NSTextField(wrappingLabelWithString: "")
    private let buttonTestTitle=NSTextField(labelWithString: "TEST MODE")
    private var testConnectButton:NSButton!
    private let buttonTestStatus=NSTextField(wrappingLabelWithString: "")
    private let progress = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let badge = NSTextField(labelWithString: "  Not connected  ")
    private let shortcut = ShortcutRecorder(frame:.zero)
    private let confirmed = NSButton(checkboxWithTitle: "Matches my app’s hold-to-dictate shortcut", target:nil, action:nil)
    private let toggle = NSButton(checkboxWithTitle: "Press once to start, again to stop",target:nil,action:nil)
    private let suppress = NSButton(checkboxWithTitle: "Replace original actions for mapped buttons",target:nil,action:nil)
    private let voiceSection = NSStackView()
    private var connectButton: NSButton!
    private var learnButton: NSButton!
    private var cancelButton: NSButton!
    private var voiceStop: NSButton!
    private var selectedIndex = 0
    private var pickerSignature = ""
    private let pageHost = NSView()
    private var pages: [WorkspacePage: NSView] = [:]
    private let sidebarNavigation=SidebarNavigation(frame:.zero)
    private var currentPage: WorkspacePage = .remotes
    private var remoteWorkspaceOpen = false
    private let remoteLibrary = NSStackView()
    private var remoteLibrarySignature = ""
    // Preview switches affect presentation only; they never change saved remotes.
    private var libraryDevices: [PluginManifest] {
        if CommandLine.arguments.contains("--render-preview") && CommandLine.arguments.contains("--preview-no-remotes") { return [] }
        return sessions.catalog.devices
    }
    private var libraryConnectedCount: Int {
        libraryDevices.filter { sessions.controllers[$0.id]?.running == true && (sessions.controllers[$0.id]?.connected ?? 0)>0 }.count
    }
    private let pageTitle = NSTextField(labelWithString: "Overview")
    private let pageSubtitle = NSTextField(wrappingLabelWithString: "")
    private let overviewTitle = NSTextField(wrappingLabelWithString: "")
    private let overviewDetail = NSTextField(wrappingLabelWithString: "")
    private let overviewConnection = NSTextField(wrappingLabelWithString: "")
    private let overviewApp = NSTextField(wrappingLabelWithString: "")
    private let overviewVoice = NSTextField(wrappingLabelWithString: "")
    private let sidebarContext = NSTextField(wrappingLabelWithString: "")
    private var overviewAction: NSButton!
    private let pluginSummary = NSTextField(wrappingLabelWithString: "")
    private let pluginSearch=NSSearchField()
    private let pluginFilter=NSSegmentedControl(labels:["All","Remotes","Apps"],trackingMode:.selectOne,target:nil,action:nil)
    private let pluginList=NSStackView()
    private var pluginListSignature=""
    private let remoteArtworkPreview=RemoteArtworkView(frame:.zero)
    private let overviewArtwork=RemoteArtworkView(frame:.zero)
    private let artworkStatus=NSTextField(wrappingLabelWithString:"")
    private var resetArtworkButton:NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let readOnly=SingleInstanceLock.isReadOnly(CommandLine.arguments)
        NSApp.setActivationPolicy(.prohibited)
        if !readOnly {
            do {
                let owner=SingleInstanceLock(directory:ConfigurationStore().url.deletingLastPathComponent())
                guard try owner.acquire() else {
                    if let pid=owner.ownerPID,let existing=NSRunningApplication(processIdentifier:pid),existing.bundleIdentifier == Bundle.main.bundleIdentifier { existing.activate(options:[]) }
                    NSApp.terminate(nil);return
                }
                sessionOwner=owner
            } catch { show(error);NSApp.terminate(nil);return }
        }

        if let index=CommandLine.arguments.firstIndex(of:"--connection-diagnostics"),CommandLine.arguments.count>index+1 {
            do {
                let catalog=PluginCatalog(bundled:Bundle.main.resourceURL!.appendingPathComponent("plugins"),user:ConfigurationStore().url.deletingLastPathComponent().appendingPathComponent("plugins"))
                var defaults=Configuration();if let device=try? catalog.find(defaults.devicePluginID,kind:"device"){defaults.profile=device.device!.profile}
                let config=try ConfigurationStore().loadCurrentRemote(defaults:defaults)
                let report=ConnectionReport.collect(config.profile);let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                try encoder.encode(report).write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]),options:.atomic)
            } catch { print(error.localizedDescription) }
            NSApp.terminate(nil);return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--dictation-button-diagnostics"),CommandLine.arguments.count>index+1 {
            do { try DictationButtonProbe.run(to:URL(fileURLWithPath:CommandLine.arguments[index+1])) }
            catch { let report=["phase":"failed","error":error.localizedDescription];if let data=try? JSONSerialization.data(withJSONObject:report){try? data.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]),options:.atomic)} }
            NSApp.terminate(nil);return
        }
        if CommandLine.arguments.contains("--list-audio-inputs") {
            for input in AudioInputs.list() { print("\(input.name) | USB=\(input.usb) | default=\(input.id == AudioInputs.defaultID()) | \(input.id)") };return
        }
        do {
            sessions = try RemoteSessions()
            // Keep the library and support installer available before a device is installed.
            // This fallback editor controller is never activated as a receiver session.
            controller = try sessions.initial ?? RemoteController()
        }
        catch { show(error); NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(readOnly ? .prohibited : .regular)
        let menu=NSMenu(),appMenu=NSMenu(),entry=NSMenuItem()
        appMenu.addItem(withTitle:"Quit JustVibe Remote",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appMenu.insertItem(withTitle:"Close Window",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w",at:0)
        entry.submenu=appMenu;menu.addItem(entry)
        let editItem=NSMenuItem();let edit=NSMenu(title:"Edit")
        for (title,action,key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(withTitle:title,action:action,keyEquivalent:key)
        }
        editItem.submenu=edit;menu.addItem(editItem)
        let viewItem=NSMenuItem();let viewMenu=NSMenu(title:"View")
        for page in WorkspacePage.allCases { let item=NSMenuItem(title:page.title,action:#selector(navigateMenu(_:)),keyEquivalent:String(page.index+1));item.target=self;item.tag=page.index;viewMenu.addItem(item) }
        viewItem.submenu=viewMenu;menu.addItem(viewItem);NSApp.mainMenu=menu
        let screenSize=NSScreen.main?.visibleFrame.size ?? NSSize(width:1440,height:1000)
        let available=NSSize(width:screenSize.width,height:max(600,screenSize.height-28))
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:min(1400,available.width),height:min(940,available.height)),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="JustVibe Remote";window.contentMinSize=NSSize(width:min(1200,available.width),height:min(840,available.height));window.delegate=self;window.center();window.appearance=NSAppearance(named:.aqua)
        let root=WorkspaceSurface(.background);window.contentView=root
        buildWorkspace(in:root)
        populatePlugins();loadEditable()
        sessions.changed={ [weak self] in self?.refresh() }
        refresh()
        if let index=CommandLine.arguments.firstIndex(of:"--render-preview"),CommandLine.arguments.count>index+1 {
            if let pageIndex=CommandLine.arguments.firstIndex(of:"--preview-page"),CommandLine.arguments.count>pageIndex+1,
               let page=WorkspacePage(rawValue:CommandLine.arguments[pageIndex+1]) { remoteWorkspaceOpen=page.isRemoteScoped;showPage(page) }
            if CommandLine.arguments.contains("--preview-compact") { window.setContentSize(window.contentMinSize) }
            if CommandLine.arguments.contains("--preview-microphone"),let index=controller.microphoneIndex { selectedIndex=index;refresh() }
            root.layoutSubtreeIfNeeded()
            if let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) {
                root.cacheDisplay(in:root.bounds,to:bitmap)
                if let png=bitmap.representation(using:.png,properties:[:]) { try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));print("Rendered JustVibe Remote preview") }
            }
            return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-add-remote-preview"),CommandLine.arguments.count>index+1 {
            let flow=AddRemoteFlow(parent:window,catalog:sessions.catalog)
            try? flow.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]),showPrompt:CommandLine.arguments.contains("--preview-agent-prompt"),compact:CommandLine.arguments.contains("--preview-compact"));return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-cursor-preview"),CommandLine.arguments.count>index+1 {
            let setup=CursorSetup(controller:controller,parent:window);try? setup.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-connection-preview"),CommandLine.arguments.count>index+1 {
            let check=ConnectionCheck(controller:controller,parent:window);try? check.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-microphone-preview"),CommandLine.arguments.count>index+1 {
            let test=MicrophoneTest(controller:controller,parent:window);try? test.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]));return
        }
        if let index=CommandLine.arguments.firstIndex(of:"--render-setup-preview"),CommandLine.arguments.count>index+1 {
            let setup=QuickSetup(controller:controller,parent:window)
            let stageIndex=CommandLine.arguments.firstIndex(of:"--preview-setup-stage")
            let stage=stageIndex.flatMap { CommandLine.arguments.count>$0+1 ? RemoteSetupStage(rawValue:CommandLine.arguments[$0+1]):nil }
            let countIndex=CommandLine.arguments.firstIndex(of:"--preview-permissions")
            let count=countIndex.flatMap { CommandLine.arguments.count>$0+1 ? Int(CommandLine.arguments[$0+1]):nil }
            try? setup.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]),stage:stage,permissionCount:count);return
        }
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        do { try sessions.activate() } catch { show(error) }

    }
    private func buildWorkspace(in root:NSView) {
        let sidebar=WorkspaceSurface(.sidebar)
        root.addSubview(sidebar);sidebar.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo:root.leadingAnchor),sidebar.topAnchor.constraint(equalTo:root.topAnchor),sidebar.bottomAnchor.constraint(equalTo:root.bottomAnchor),sidebar.widthAnchor.constraint(equalToConstant:218)])
        let mark=BrandMark(frame:.zero)
        mark.widthAnchor.constraint(equalToConstant:44).isActive=true;mark.heightAnchor.constraint(equalToConstant:44).isActive=true
        let wordmark=vertical(spacing:3)
        wordmark.addArrangedSubview(label("JustVibe",size:17,weight:.bold))
        wordmark.addArrangedSubview(label("Remote",size:11,weight:.medium))
        let identity=horizontal([mark,wordmark,spacer()],spacing:10)
        pin(identity,to:sidebar,top:28,left:18,right:14)
        sidebar.addSubview(sidebarNavigation);sidebarNavigation.translatesAutoresizingMaskIntoConstraints=false
        sidebarNavigation.selected={ [weak self] page in self?.showPage(page) }
        let divider=NSBox();divider.boxType = .separator
        sidebar.addSubview(divider);divider.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([sidebarNavigation.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:8),sidebarNavigation.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-8),sidebarNavigation.topAnchor.constraint(equalTo:identity.bottomAnchor,constant:20),sidebarNavigation.bottomAnchor.constraint(equalTo:divider.topAnchor,constant:-12),divider.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:20),divider.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-20),divider.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-62)])
        sidebarContext.font = .systemFont(ofSize:11);sidebarContext.textColor = .rvMuted
        sidebar.addSubview(sidebarContext);sidebarContext.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([sidebarContext.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:20),sidebarContext.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-18),sidebarContext.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-24)])

        let heading=vertical(spacing:5);pageTitle.font = .systemFont(ofSize:30,weight:.bold);pageTitle.textColor = .rvInk;heading.addArrangedSubview(pageTitle)
        pageSubtitle.font = .systemFont(ofSize:13);pageSubtitle.textColor = .rvMuted;heading.addArrangedSubview(pageSubtitle)
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        pageSubtitle.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        badge.font = .systemFont(ofSize:11,weight:.medium);badge.textColor = .rvMuted
        connectButton=button("Connect remote",#selector(connect),primary:true)
        voiceStop=button("Stop voice",#selector(stopVoice));voiceStop.isHidden=true
        let header=horizontal([heading,spacer(),voiceStop],spacing:12)
        root.addSubview(header);header.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:28),header.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),header.topAnchor.constraint(equalTo:root.topAnchor,constant:24),header.heightAnchor.constraint(equalToConstant:68)])
        status.font = .systemFont(ofSize:11);status.textColor = .rvMuted
        root.addSubview(status);status.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([status.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:30),status.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),status.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16),status.heightAnchor.constraint(equalToConstant:32)])
        root.addSubview(pageHost);pageHost.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([pageHost.leadingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:28),pageHost.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),pageHost.topAnchor.constraint(equalTo:header.bottomAnchor,constant:16),pageHost.bottomAnchor.constraint(equalTo:status.topAnchor,constant:-12)])
        pages[.remotes]=makeRemotes();pages[.plugins]=makePlugins();pages[.overview]=makeOverview();pages[.buttons]=makeButtons();pages[.voice]=makeVoice();pages[.apps]=makeApps();pages[.devices]=makeDevices();pages[.help]=makeHelp()
        for page in WorkspacePage.allCases { guard let view=pages[page] else { continue };pageHost.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo:pageHost.leadingAnchor),view.trailingAnchor.constraint(equalTo:pageHost.trailingAnchor),view.topAnchor.constraint(equalTo:pageHost.topAnchor),view.bottomAnchor.constraint(equalTo:pageHost.bottomAnchor)])
        }
        showPage(.remotes)
    }

    private func scrollPage(_ content:NSStackView,maximumWidth:CGFloat? = nil)->NSView {
        let scroll=NSScrollView();scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let document=WorkspaceDocument();document.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=document
        content.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(content)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),content.leadingAnchor.constraint(equalTo:document.leadingAnchor),content.topAnchor.constraint(equalTo:document.topAnchor),content.bottomAnchor.constraint(equalTo:document.bottomAnchor)])
        if let maximumWidth {
            let fill=content.widthAnchor.constraint(equalTo:document.widthAnchor);fill.priority = .defaultHigh
            NSLayoutConstraint.activate([fill,content.widthAnchor.constraint(lessThanOrEqualToConstant:maximumWidth),content.trailingAnchor.constraint(lessThanOrEqualTo:document.trailingAnchor)])
        } else { content.trailingAnchor.constraint(equalTo:document.trailingAnchor).isActive=true }
        return scroll
    }
    private func section(_ title:String,_ detail:String? = nil)->NSStackView {
        let content=vertical(spacing:10)
        content.addArrangedSubview(label(title,size:16,weight:.semibold))
        if let detail { let text=NSTextField(wrappingLabelWithString:detail);text.font = .systemFont(ofSize:12);text.textColor = .rvMuted;content.addArrangedSubview(text) }
        return content
    }
    private func addCard(_ content:NSStackView,to stack:NSStackView) {
        for child in content.arrangedSubviews {
            child.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            child.widthAnchor.constraint(lessThanOrEqualTo:content.widthAnchor).isActive=true
        }
        let panel=card(content,padding:20);stack.addArrangedSubview(panel);panel.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
    }
    private func makeRemotes()->NSView {
        let stack=vertical(spacing:18)
        remoteLibrary.orientation = .vertical;remoteLibrary.alignment = .leading;remoteLibrary.spacing=14
        stack.addArrangedSubview(remoteLibrary);remoteLibrary.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        rebuildRemoteLibrary()
        return scrollPage(stack)
    }
    private func rebuildRemoteLibrary() {
        let signature="library:" + libraryDevices.map { remote in
            let session=sessions.controllers[remote.id]
            return remote.id + remote.name + (session?.config.appPluginID ?? "") + String(session?.running ?? false) + String(session?.connected ?? 0) + (session?.running == false ? session?.status ?? "" : "") + String(session?.config.remoteSetupCompleted ?? false) + (session?.config.remoteSetupCheckpoint?.stage.rawValue ?? "") + (session?.artwork.revision.uuidString ?? "")
        }.joined(separator:"|")
        guard signature != remoteLibrarySignature else { return };remoteLibrarySignature=signature
        for view in remoteLibrary.arrangedSubviews { remoteLibrary.removeArrangedSubview(view);view.removeFromSuperview() }
        if libraryDevices.isEmpty {
            let welcome=section("Set up your first remote","Add support for your remote, then we’ll guide you through choosing an app and setting up its controls.")
            let artwork=BrandMark(frame:.zero)
            artwork.widthAnchor.constraint(equalToConstant:160).isActive=true
            artwork.heightAnchor.constraint(equalToConstant:160).isActive=true
            let details=vertical(spacing:16)
            details.addArrangedSubview(welcome)
            details.addArrangedSubview(button("Add a new remote…",#selector(addRemote),primary:true))
            details.addArrangedSubview(label("Start with one. Add more whenever you need them.",size:12,color:.rvMuted))
            let panel=card(horizontal([artwork,details,spacer()],spacing:28),padding:28)
            remoteLibrary.addArrangedSubview(panel);panel.widthAnchor.constraint(equalTo:remoteLibrary.widthAnchor).isActive=true
            return
        }
        let intro=horizontal([label("YOUR COLLECTION",size:10,weight:.semibold,color:.rvMuted),spacer(),label("\(libraryDevices.count) installed",size:11,color:.rvMuted)],spacing:12)
        remoteLibrary.addArrangedSubview(intro)
        intro.widthAnchor.constraint(equalTo:remoteLibrary.widthAnchor).isActive=true
        for (remoteIndex,remote) in libraryDevices.enumerated() {
            let content=vertical(spacing:14)
            content.addArrangedSubview(label(String(format:"REMOTE %02d",remoteIndex+1),size:10,weight:.semibold,color:.rvAccent))
            let name=NSTextField(wrappingLabelWithString:remote.name);name.font = .systemFont(ofSize:23,weight:.bold);name.textColor = .rvInk
            let session=sessions.controllers[remote.id]
            let connected=session?.running == true && (session?.connected ?? 0)>0
            let state=connected ? "Connected" : session?.running == true ? "Waiting for receiver" : "Not connected"
            let stateLabel=label("  \(connected ? "● ":"")\(state)  ",size:11,weight:.semibold,color:connected ? .systemTeal:.rvMuted)
            stateLabel.wantsLayer=true;stateLabel.layer?.cornerRadius=8
            stateLabel.layer?.backgroundColor=(connected ? NSColor.systemTeal:NSColor.rvMuted).withAlphaComponent(0.09).cgColor
            content.addArrangedSubview(name);content.addArrangedSubview(stateLabel)
            let appID=session?.config.appPluginID
            let app=sessions.catalog.apps.first { $0.id == appID }
            let appSummary=session?.config.followActiveApp == true ? "Automatically follows the active app" : appID == Configuration.noSpecificAppID ? "Shared controls in the active app" : app.map { "Controls \($0.name)" } ?? "Choose an app during setup"
            content.addArrangedSubview(label(appSummary,size:13,color:.rvMuted))
            if session?.config.remoteSetupCompleted != true {
                content.addArrangedSubview(label("Setup in progress · pick up where you left off",size:12,color:.rvMuted))
            }
            if let session,!session.running,!session.status.hasPrefix("Ready to set up"),!session.status.hasPrefix("Stopped;") {
                let issue=NSTextField(wrappingLabelWithString:session.status);issue.font = .systemFont(ofSize:12);issue.textColor = .systemOrange;content.addArrangedSubview(issue)
            }
            let open=button(session?.config.remoteSetupCompleted == true ? "Open remote →":session?.config.remoteSetupCheckpoint == nil ? "Set up remote →":"Continue setup →",#selector(openRemote(_:)),primary:true);open.identifier=NSUserInterfaceItemIdentifier(remote.id);open.setAccessibilityLabel("Open \(remote.name)")
            let connection=button(session?.running == true ? "Disconnect":"Connect",#selector(connectRemote(_:)))
            connection.identifier=NSUserInterfaceItemIdentifier(remote.id);connection.setAccessibilityLabel("\(session?.running == true ? "Disconnect":"Connect") \(remote.name)")
            content.addArrangedSubview(horizontal([open,connection,spacer()],spacing:10))
            let art=RemoteArtworkView(frame:.zero);art.reference=session?.artwork.image;art.remoteLayout=remote.device?.layout
            let stage=WorkspaceSurface(.artwork)
            stage.widthAnchor.constraint(equalToConstant:158).isActive=true;stage.heightAnchor.constraint(equalToConstant:224).isActive=true
            stage.addSubview(art);art.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([art.centerXAnchor.constraint(equalTo:stage.centerXAnchor),art.centerYAnchor.constraint(equalTo:stage.centerYAnchor),art.widthAnchor.constraint(equalToConstant:104),art.heightAnchor.constraint(equalToConstant:190)])
            let row=horizontal([stage,content,spacer()],spacing:28)
            let panel=card(row,padding:24);remoteLibrary.addArrangedSubview(panel);panel.widthAnchor.constraint(equalTo:remoteLibrary.widthAnchor).isActive=true
        }
        let more=section("Add another remote","Give another remote its own apps and controls.")
        let footer=horizontal([more,spacer(),button("Add a new remote…",#selector(addRemote))],spacing:20)
        let panel=card(footer,padding:20)
        remoteLibrary.addArrangedSubview(panel);panel.widthAnchor.constraint(equalTo:remoteLibrary.widthAnchor).isActive=true
    }
    @objc private func openRemote(_ sender:NSButton) {
        guard let id=sender.identifier?.rawValue,confirmVoiceDraft() else { return }
        do {
            guard let session=sessions.controllers[id] else { throw JustVibeRemoteError.message("This remote is no longer available. Reload its plugin.") }
            controller.cancelLearning()
            controller=session
            remoteWorkspaceOpen=true;selectedIndex=0;populatePlugins();loadEditable();showPage(.overview);refresh()
            if !controller.config.remoteSetupCompleted { quickSetup() }
        } catch { show(error) }
    }
    @objc private func connectRemote(_ sender:NSButton) {
        guard let id=sender.identifier?.rawValue,let session=sessions.controllers[id] else { return }
        if session.running { do { try session.stop() } catch { show(error) } }
        else { session.start() }
        refresh()
    }
    @objc private func addRemote() {
        guard addRemoteFlow == nil else { return }
        let flow=AddRemoteFlow(parent:window,catalog:sessions.catalog)
        addRemoteFlow=flow
        flow.finished={ [weak self] in self?.addRemoteFlow=nil }
        flow.openRemote={ [weak self] id in
            let sender=NSButton();sender.identifier=NSUserInterfaceItemIdentifier(id);self?.openRemote(sender)
        }
        flow.managePlugins={ [weak self] in self?.openPlugins() }
        flow.show()
    }
    @objc private func openRemotes() { showPage(.remotes) }
    @objc private func openPlugins() { showPage(.plugins) }

    private func makeOverview()->NSView {
        let stack=vertical(spacing:16)
        let hero=vertical(spacing:12)
        hero.addArrangedSubview(label("YOUR NEXT STEP",size:10,weight:.semibold,color:.rvAccent))
        overviewTitle.font = .systemFont(ofSize:23,weight:.bold);overviewTitle.textColor = .rvInk;hero.addArrangedSubview(overviewTitle)
        overviewDetail.font = .systemFont(ofSize:13);overviewDetail.textColor = .rvMuted;hero.addArrangedSubview(overviewDetail)
        overviewAction=button("Continue setup",#selector(overviewNext),primary:true);hero.addArrangedSubview(overviewAction)
        overviewArtwork.widthAnchor.constraint(equalToConstant:110).isActive=true;overviewArtwork.heightAnchor.constraint(equalToConstant:180).isActive=true
        hero.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let stage=WorkspaceSurface(.artwork)
        stage.addSubview(overviewArtwork);overviewArtwork.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([stage.widthAnchor.constraint(equalToConstant:154),stage.heightAnchor.constraint(equalToConstant:208),overviewArtwork.centerXAnchor.constraint(equalTo:stage.centerXAnchor),overviewArtwork.centerYAnchor.constraint(equalTo:stage.centerYAnchor)])
        let heroPanel=card(horizontal([hero,spacer(),stage],spacing:24),padding:24)
        stack.addArrangedSubview(heroPanel);heroPanel.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        let health=section("This remote")
        for (title,field,selector) in [("Remote",overviewConnection,#selector(openDevices)),("App profile",overviewApp,#selector(openApps)),("Voice input",overviewVoice,#selector(openVoice))] {
            field.font = .systemFont(ofSize:12);field.textColor = .rvMuted
            let description=vertical(spacing:4);description.addArrangedSubview(label(title,size:13,weight:.semibold));description.addArrangedSubview(field)
            let row=horizontal([description,spacer(),button("Review",selector)],spacing:16);health.addArrangedSubview(row);row.widthAnchor.constraint(equalTo:health.widthAnchor).isActive=true
        }
        addCard(health,to:stack)
        let start=section("Configure this remote","Start with the buttons you use most. You can link the rest whenever you need them.")
        start.addArrangedSubview(horizontal([button("Customize buttons",#selector(openButtons)),button("Voice & microphone",#selector(openVoice)),spacer()],spacing:10))
        addCard(start,to:stack)
        return scrollPage(stack)
    }
    private func makeButtons()->NSView {
        let page=NSView()
        appIconSelector.selected={ [weak self] appID in self?.selectAppProfile(appID) }
        let intro=vertical(spacing:4)
        intro.addArrangedSubview(appIconSelector)
        appIconSelector.widthAnchor.constraint(equalTo:intro.widthAnchor).isActive=true
        appIconSelector.heightAnchor.constraint(equalToConstant:88).isActive=true
        progress.font = .systemFont(ofSize:11);progress.textColor = .rvMuted
        let testInfo=vertical(spacing:4)
        buttonTestTitle.font = .systemFont(ofSize:13,weight:.semibold);buttonTestTitle.textColor = .rvAccent
        testInfo.addArrangedSubview(buttonTestTitle)
        buttonTestStatus.font = .systemFont(ofSize:11);buttonTestStatus.textColor = .rvMuted
        testInfo.addArrangedSubview(buttonTestStatus)
        testConnectButton=button("Connect to test",#selector(connect))
        let testBanner=card(horizontal([testInfo,spacer(),testConnectButton],spacing:12),padding:12)
        intro.addArrangedSubview(testBanner);testBanner.widthAnchor.constraint(equalTo:intro.widthAnchor).isActive=true
        buttonTestStatus.widthAnchor.constraint(lessThanOrEqualTo:intro.widthAnchor,constant:-170).isActive=true
        intro.addArrangedSubview(horizontal([label("Press your remote to highlight its buttons. Switch to your app to use its actions.",size:11,color:.rvMuted),spacer(),progress],spacing:8))
        intro.arrangedSubviews.last?.widthAnchor.constraint(equalTo:intro.widthAnchor).isActive=true
        mappingBoard=RemoteMappingBoard(canvas:canvas)
        mappingBoard.selected={ [weak self] id in self?.selectControl(id) }
        mappingBoard.assigned={ [weak self] id,action in
            guard let self else { return };self.selectControl(id)
            var config=self.controller.config;config.bindings[self.selectedIndex].action=action
            do { try self.controller.update(config);self.refresh() } catch { self.show(error) }
        }
        mappingBoard.learn={ [weak self] id in self?.selectControl(id);self?.learn() }
        mappingBoard.cancelLearning={ [weak self] in self?.cancelLearning() }
        canvas.selected={ [weak self] id in self?.selectControl(id) }
        // Keep the complete remote and its mappings in the available workspace.
        // The inspector sits beside it, so it never reduces the diagram's height.
        let physical=vertical(spacing:6)
        physical.addArrangedSubview(label("REMOTE BUTTON",size:10,weight:.semibold,color:.rvMuted))
        bindingPicker.target=self;bindingPicker.action=#selector(pickBinding);bindingPicker.setAccessibilityLabel("Selected remote button")
        physical.addArrangedSubview(bindingPicker)
        linked.font = .systemFont(ofSize:11,weight:.medium);physical.addArrangedSubview(linked)
        learnButton=button("Link button",#selector(learn));cancelButton=button("Cancel",#selector(cancelLearning));cancelButton.isHidden=true
        physical.addArrangedSubview(horizontal([learnButton,cancelButton],spacing:4))
        let assignment=vertical(spacing:6)
        assignment.addArrangedSubview(label("ACTION",size:10,weight:.semibold,color:.rvMuted))
        actionPicker.target=self;actionPicker.action=#selector(changeAction);actionPicker.setAccessibilityLabel("Button action")
        assignment.addArrangedSubview(actionPicker)
        actionHelp.font = .systemFont(ofSize:11);actionHelp.textColor = .rvMuted
        actionHelp.maximumNumberOfLines=3;actionHelp.cell?.wraps=true;assignment.addArrangedSubview(actionHelp)
        voiceSection.orientation = .vertical;voiceSection.alignment = .leading;voiceSection.spacing=6
        voiceSection.addArrangedSubview(label("APP DICTATION SHORTCUT",size:10,weight:.semibold,color:.rvMuted))
        dictationBinding.font = .systemFont(ofSize:19,weight:.semibold);dictationBinding.textColor = .rvAccent
        voiceSection.addArrangedSubview(dictationBinding)
        dictationBindingHelp.font = .systemFont(ofSize:11);dictationBindingHelp.textColor = .rvMuted
        dictationBindingHelp.maximumNumberOfLines=3;voiceSection.addArrangedSubview(dictationBindingHelp)
        voiceSection.addArrangedSubview(button("Review voice settings →",#selector(openVoice)))
        let columns=vertical(spacing:22)
        columns.addArrangedSubview(label("Button details",size:16,weight:.semibold))
        for section in [physical,assignment,voiceSection] {
            columns.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo:columns.widthAnchor).isActive=true
        }
        for column in [physical,assignment,voiceSection] {
            for child in column.arrangedSubviews {
                child.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
                child.widthAnchor.constraint(lessThanOrEqualTo:column.widthAnchor).isActive=true
            }
        }
        actionHelp.widthAnchor.constraint(equalTo:assignment.widthAnchor).isActive=true
        dictationBindingHelp.widthAnchor.constraint(equalTo:voiceSection.widthAnchor).isActive=true
        let inspector=card(columns,padding:18)
        for view in [intro,mappingBoard!,inspector] { page.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo:page.topAnchor),intro.leadingAnchor.constraint(equalTo:page.leadingAnchor),intro.trailingAnchor.constraint(equalTo:page.trailingAnchor),
            mappingBoard.topAnchor.constraint(equalTo:intro.bottomAnchor,constant:12),mappingBoard.leadingAnchor.constraint(equalTo:page.leadingAnchor),mappingBoard.bottomAnchor.constraint(equalTo:page.bottomAnchor),
            inspector.leadingAnchor.constraint(equalTo:mappingBoard.trailingAnchor,constant:20),inspector.trailingAnchor.constraint(equalTo:page.trailingAnchor),inspector.topAnchor.constraint(equalTo:mappingBoard.topAnchor,constant:12),inspector.bottomAnchor.constraint(lessThanOrEqualTo:page.bottomAnchor),inspector.widthAnchor.constraint(equalToConstant:250)
        ])
        return page
    }
    private func makeVoice()->NSView {
        let stack=vertical(spacing:16)
        let mic=section("Hear your remote", "Choose a microphone, record a short clip, then play it back.")
        voiceMicrophoneHost.orientation = .vertical;voiceMicrophoneHost.alignment = .leading
        mic.addArrangedSubview(voiceMicrophoneHost);addCard(mic,to:stack)
        voiceMicrophoneHost.widthAnchor.constraint(equalTo:mic.widthAnchor).isActive=true
        return scrollPage(stack,maximumWidth:760)
    }
    private func clearVoiceMicrophoneTest() {
        guard !voiceTestClosing else { return };voiceTestClosing=true
        defer { voiceTestClosing=false }
        voiceMicrophonePanel?.close();voiceMicrophonePanel?.removeFromSuperview()
        voiceMicrophonePanel=nil;voiceMicrophoneController=nil
    }
    private func refreshVoiceTests() {
        if currentPage == .voice && remoteWorkspaceOpen && !voiceTestClosing {
            if voiceMicrophoneController !== controller || voiceMicrophonePanel == nil {
                clearVoiceMicrophoneTest()
                let panel=VoiceMicrophonePanel(controller:controller)
                voiceMicrophonePanel=panel;voiceMicrophoneController=controller;voiceMicrophoneHost.addArrangedSubview(panel)
                panel.widthAnchor.constraint(equalTo:voiceMicrophoneHost.widthAnchor).isActive=true
            }
        } else if currentPage != .voice { clearVoiceMicrophoneTest() }
    }
    @objc private func editSupportedAppShortcut(_ sender:NSButton) {
        guard let id=sender.identifier?.rawValue else { return }
        selectAppProfile(id)
        guard controller.config.appPluginID == id else { return }
        editVoiceSettings()
    }
    @objc private func editVoiceSettings() {
        guard controller.appPlugin?.app?.supports(.dictate) == true else { return }
        clearVoiceMicrophoneTest();loadEditable()
        let alert=NSAlert();alert.messageText="Dictation shortcut for \(controller.appPlugin?.name ?? "this app")"
        alert.informativeText="Match the shortcut configured in this app. These settings apply only to this app profile."
        alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel")
        let content=vertical(spacing:12)
        content.addArrangedSubview(shortcut);shortcut.setAccessibilityLabel("Record dictation shortcut")
        content.addArrangedSubview(label("Click the field and press your shortcut keys. Esc cancels recording.",size:12,color:.rvMuted))
        content.addArrangedSubview(confirmed);content.addArrangedSubview(toggle)
        content.frame=NSRect(x:0,y:0,width:460,height:150)
        shortcut.widthAnchor.constraint(equalToConstant:460).isActive=true;shortcut.heightAnchor.constraint(equalToConstant:36).isActive=true
        alert.accessoryView=content
        while alert.runModal() == .alertFirstButtonReturn { if saveVoiceSettings() { break } }
        loadEditable();refresh()
    }
    private func makeApps()->NSView {
        let stack=vertical(spacing:16)
        let heading=horizontal([label("Supported apps",size:16,weight:.semibold),spacer(),button("Add app…",#selector(addApplication))],spacing:12)
        stack.addArrangedSubview(heading);heading.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        let placeholder=AppDropPlaceholder(frame:.zero)
        placeholder.target=self;placeholder.action=#selector(addApplication)
        stack.addArrangedSubview(placeholder)
        placeholder.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        placeholder.heightAnchor.constraint(equalToConstant:100).isActive=true
        supportedAppList.orientation = .vertical;supportedAppList.alignment = .leading;supportedAppList.spacing=12
        stack.addArrangedSubview(supportedAppList);supportedAppList.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        rebuildSupportedApps()
        let drop=AppListDropContainer(frame:.zero)
        drop.highlightChanged={ [weak placeholder] active in placeholder?.receiving=active }
        drop.dropped={ [weak self] url in self?.addDroppedApplication(at:url) }
        let scroll=scrollPage(stack);drop.addSubview(scroll);scroll.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:drop.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:drop.trailingAnchor),scroll.topAnchor.constraint(equalTo:drop.topAnchor),scroll.bottomAnchor.constraint(equalTo:drop.bottomAnchor)])
        return drop
    }
    private func rebuildSupportedApps() {
        let apps=sessions.catalog.apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let signature=controller.config.devicePluginID + "|" + controller.config.appPluginID + "|" + apps.map { $0.id + $0.name + $0.version }.joined(separator:"|")
        guard signature != supportedAppSignature else { return };supportedAppSignature=signature
        for child in supportedAppList.arrangedSubviews { supportedAppList.removeArrangedSubview(child);child.removeFromSuperview() }
        for plugin in apps {
            let icon=NSImageView();icon.imageScaling = .scaleProportionallyUpOrDown
            let configured=plugin.id == controller.config.appPluginID ? controller.config.targetAppPath : controller.config.appMappings[AppRouting.key(controller.config.devicePluginID,plugin.id)]?.targetAppPath ?? ""
            let url = !configured.isEmpty ? URL(fileURLWithPath:configured) : plugin.app?.targets["macos"]?.bundleIds.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }.first
            icon.image=url.map { NSWorkspace.shared.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"app.fill",accessibilityDescription:nil)
            icon.widthAnchor.constraint(equalToConstant:42).isActive=true;icon.heightAnchor.constraint(equalToConstant:42).isActive=true
            let info=vertical(spacing:5)
            info.addArrangedSubview(label(plugin.name,size:16,weight:.semibold))
            info.addArrangedSubview(label(plugin.app?.supports(.dictate) == true ? "Buttons and voice input":"Button controls",size:12,color:.rvMuted))
            info.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            let edit=button("Configure →",#selector(configureSupportedApp(_:)))
            edit.identifier=NSUserInterfaceItemIdentifier(plugin.id);edit.setAccessibilityLabel("Configure \(plugin.name)")
            var items:[NSView]=[icon,info,spacer()]
            if plugin.app?.supports(.dictate) == true {
                let voice=button("Dictation shortcut…",#selector(editSupportedAppShortcut(_:)))
                voice.identifier=NSUserInterfaceItemIdentifier(plugin.id);items.append(voice)
            }
            items.append(edit)
            let panel=card(horizontal(items,spacing:16),padding:18)
            supportedAppList.addArrangedSubview(panel);panel.widthAnchor.constraint(equalTo:supportedAppList.widthAnchor).isActive=true
        }
        if apps.isEmpty {
            addCard(section("No supported apps yet","Add an app, or drop one here from Finder."),to:supportedAppList)
        }
    }
    @objc private func configureSupportedApp(_ sender:NSButton) {
        guard let appID=sender.identifier?.rawValue,confirmVoiceDraft() else { return }
        do {
            if appID != controller.config.appPluginID { try controller.selectPlugins(deviceID:controller.config.devicePluginID,appID:appID) }
            selectedIndex=0;populatePlugins();loadEditable();refresh();showPage(.buttons)
        } catch { show(error) }
    }
    private func makeDevices()->NSView {
        let stack=vertical(spacing:16)
        let device=section("Connection","Connect this remote’s receiver. To configure a different remote, return to Remotes.")
        device.addArrangedSubview(horizontal([badge,spacer(),connectButton],spacing:12))
        device.addArrangedSubview(horizontal([button("Connection & permissions…",#selector(checkConnection)),button("Cursor speed…",#selector(setupCursor)),spacer()],spacing:10))
        device.addArrangedSubview(button("Run setup guide…",#selector(quickSetup)));addCard(device,to:stack)
        let routing=section("App switching","Automatically use the active app’s saved controls and dictation shortcut. Other apps use shared controls when configured.")
        followApp.target=self;followApp.action=#selector(changeRouting);routing.addArrangedSubview(followApp)
        routeLabel.font = .systemFont(ofSize:12);routeLabel.textColor = .rvMuted;routing.addArrangedSubview(routeLabel);addCard(routing,to:stack)
        let artwork=section("Remote artwork","Use this remote’s design, or choose a front-facing photo. The same artwork identifies it throughout the app.")
        remoteArtworkPreview.widthAnchor.constraint(equalToConstant:100).isActive=true;remoteArtworkPreview.heightAnchor.constraint(equalToConstant:165).isActive=true
        artworkStatus.font = .systemFont(ofSize:12);artworkStatus.textColor = .rvMuted
        let artworkControls=vertical(spacing:12);artworkControls.addArrangedSubview(artworkStatus)
        artworkControls.addArrangedSubview(button("Choose image…",#selector(chooseArtwork)))
        resetArtworkButton=button("Use remote design",#selector(resetArtwork));artworkControls.addArrangedSubview(resetArtworkButton)
        artwork.addArrangedSubview(horizontal([remoteArtworkPreview,artworkControls,spacer()],spacing:20));addCard(artwork,to:stack)
        let behavior=section("Button behavior","Replace the original behavior only for buttons you have mapped. Unmapped buttons keep their normal behavior.")
        behavior.addArrangedSubview(suppress);behavior.addArrangedSubview(button("Save button behavior",#selector(saveBehavior)));addCard(behavior,to:stack)
        return scrollPage(stack)
    }
    private func makePlugins()->NSView {
        let stack=vertical(spacing:18)
        pluginSearch.placeholderString="Search plugins";pluginSearch.setAccessibilityLabel("Search installed plugins")
        pluginSearch.target=self;pluginSearch.action=#selector(filterPlugins);pluginSearch.sendsSearchStringImmediately=true
        pluginFilter.selectedSegment=0;pluginFilter.target=self;pluginFilter.action=#selector(filterPlugins);pluginFilter.setAccessibilityLabel("Plugin type")
        let toolbar=horizontal([pluginSearch,pluginFilter],spacing:16)
        stack.addArrangedSubview(toolbar);toolbar.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        pluginSearch.widthAnchor.constraint(greaterThanOrEqualToConstant:180).isActive=true
        pluginSummary.font = .systemFont(ofSize:12);pluginSummary.textColor = .rvMuted;stack.addArrangedSubview(pluginSummary)
        pluginList.orientation = .vertical;pluginList.alignment = .leading;pluginList.spacing=14
        stack.addArrangedSubview(pluginList);pluginList.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        rebuildPluginList()
        let install=section("Add more plugins","Put a remote or app plugin in your plugin folder, then reload to see it here.")
        install.addArrangedSubview(horizontal([button("Open plugin folder…",#selector(openPluginFolder)),button("Reload plugins",#selector(reloadPlugins)),spacer()],spacing:10))
        install.addArrangedSubview(label("Reloading disconnects all remotes. Reconnect them when you’re ready.",size:11,color:.rvMuted))
        addCard(install,to:stack)
        return scrollPage(stack)
    }
    @objc private func filterPlugins() { rebuildPluginList() }
    private func rebuildPluginList() {
        let query=pluginSearch.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let signature="plugins:"+sessions.catalog.plugins.map { "\($0.id)|\($0.name)|\($0.version)|\($0.author)|\(sessions.controllers[$0.id]?.artwork.revision.uuidString ?? "")" }.joined(separator:";")+query+String(pluginFilter.selectedSegment)+sessions.catalog.diagnostics.joined()
        guard signature != pluginListSignature else { return };pluginListSignature=signature
        for view in pluginList.arrangedSubviews { pluginList.removeArrangedSubview(view);view.removeFromSuperview() }
        let matches=sessions.catalog.plugins.filter { plugin in
            (pluginFilter.selectedSegment == 0 || plugin.kind == (pluginFilter.selectedSegment == 1 ? "device":"app")) &&
            (query.isEmpty || [plugin.name,plugin.author,plugin.id].contains { $0.localizedCaseInsensitiveContains(query) })
        }
        pluginSummary.stringValue="\(sessions.catalog.plugins.count) installed · \(sessions.catalog.devices.count) remote · \(sessions.catalog.apps.count) app" + (query.isEmpty && pluginFilter.selectedSegment == 0 ? "":" · \(matches.count) shown")
        if matches.isEmpty {
            addCard(section(sessions.catalog.plugins.isEmpty ? "No plugins installed yet":"No matching plugins",sessions.catalog.plugins.isEmpty ? "Add a plugin below to get started.":"Try another search or choose All to see your installed plugins."),to:pluginList)
        }
        for (kind,title,detail) in [("device","Remote plugins","Support for your remote’s buttons and receiver."),("app","App plugins","Actions your remotes can use in an app.")] {
            let plugins=matches.filter { $0.kind == kind }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            guard !plugins.isEmpty else { continue }
            let group=section("\(title) · \(plugins.count)",detail)
            pluginList.addArrangedSubview(group);group.widthAnchor.constraint(equalTo:pluginList.widthAnchor).isActive=true
            for plugin in plugins {
                let info=vertical(spacing:7)
                info.addArrangedSubview(label(plugin.name,size:17,weight:.semibold))
                info.addArrangedSubview(label("Version \(plugin.version) · By \(plugin.author)",size:12,color:.rvMuted))
                let description: String
                if let app=plugin.app {
                    description=RemoteAction.allCases.filter { $0 != .native && app.supports($0) }.map(\.title).joined(separator:" · ")
                } else {
                    description=plugin.device?.layout.map { "\($0.buttons.count) controls · Ready to set up" } ?? "Ready to set up"
                }
                let summary=NSTextField(wrappingLabelWithString:description);summary.font = .systemFont(ofSize:12);summary.textColor = .rvMuted
                info.addArrangedSubview(summary);summary.widthAnchor.constraint(lessThanOrEqualTo:info.widthAnchor).isActive=true
                let icon:NSView
                if kind == "device" {
                    let artwork=RemoteArtworkView(frame:.zero)
                    artwork.reference=sessions.controllers[plugin.id]?.artwork.image;artwork.remoteLayout=plugin.device?.layout
                    icon=artwork
                    icon.widthAnchor.constraint(equalToConstant:52).isActive=true;icon.heightAnchor.constraint(equalToConstant:88).isActive=true
                } else {
                    let symbol=NSImageView()
                    if let applicationURL=installedApplicationURL(for:plugin) {
                        symbol.image=NSWorkspace.shared.icon(forFile:applicationURL.path)
                    } else {
                        symbol.image=NSImage(systemSymbolName:"app.badge",accessibilityDescription:nil)
                        symbol.contentTintColor = .rvAccent
                    }
                    symbol.setAccessibilityLabel("\(plugin.name) app icon")
                    symbol.imageScaling = .scaleProportionallyUpOrDown;icon=symbol
                    icon.widthAnchor.constraint(equalToConstant:52).isActive=true;icon.heightAnchor.constraint(equalToConstant:52).isActive=true
                }
                let action: NSButton
                if kind == "device" {
                    action=button("Open remote →",#selector(openRemote(_:)));action.identifier=NSUserInterfaceItemIdentifier(plugin.id);action.setAccessibilityLabel("Open \(plugin.name)")
                } else {
                    action=button("Choose a remote →",#selector(openRemotes));action.setAccessibilityLabel("Choose a remote to configure \(plugin.name)")
                }
                let row=horizontal([icon,info,spacer(),action],spacing:18)
                let panel=card(row,padding:20);panel.toolTip=plugin.id
                pluginList.addArrangedSubview(panel);panel.widthAnchor.constraint(equalTo:pluginList.widthAnchor).isActive=true
                info.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
            }
        }
        if !sessions.catalog.diagnostics.isEmpty {
            addCard(section("Some plugins couldn’t load",sessions.catalog.diagnostics.joined(separator:"\n")),to:pluginList)
        }
    }
    private func installedApplicationURL(for plugin:PluginManifest)->URL? {
        func application(at path:String)->URL? {
            guard !path.isEmpty else { return nil }
            let url=URL(fileURLWithPath:path)
            return url.pathExtension.lowercased() == "app" && FileManager.default.fileExists(atPath:path) && Bundle(url:url) != nil ? url:nil
        }
        for session in sessions.controllers.sorted(by:{$0.key < $1.key}).map(\.value) {
            if session.config.appPluginID == plugin.id,let url=application(at:session.config.targetAppPath) { return url }
            if let mapping=session.config.appMappings[AppRouting.key(session.config.devicePluginID,plugin.id)],let url=application(at:mapping.targetAppPath) { return url }
        }
        if let url=plugin.app?.targets["macos"]?.bundleIds.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }).first { return url }
        let names=plugin.app?.targets["macos"]?.names ?? []
        return NSWorkspace.shared.runningApplications.first(where:{ names.contains($0.localizedName ?? "") })?.bundleURL
    }
    private func makeHelp()->NSView {
        let stack=vertical(spacing:16)
        let setup=section("A clear path from setup to your first action","1. Open a remote from Remotes.\n2. Choose an app inside that remote.\n3. Link its buttons and assign actions.\n4. Configure voice and microphone if you need dictation.")
        setup.addArrangedSubview(button("Choose a remote →",#selector(openRemotes),primary:true));addCard(setup,to:stack)
        let fix=section("Something isn’t working?","No button response: check connection and permissions.\nWrong button action: link the physical button again.\nDictation without text: check the target app’s microphone and shortcut.")
        fix.addArrangedSubview(horizontal([button("Connection & permissions…",#selector(checkConnection)),button("Voice settings →",#selector(openVoice)),spacer()],spacing:10));addCard(fix,to:stack)
        return scrollPage(stack)
    }
    private func showPage(_ page:WorkspacePage) {
        if page.isRemoteScoped && !remoteWorkspaceOpen { showPage(.remotes);return }
        if currentPage == .buttons && page != .buttons { controller.cancelLearning() }
        if currentPage == .voice && page != .voice { clearVoiceMicrophoneTest() }
        if page == .remotes { remoteWorkspaceOpen=false;rebuildRemoteLibrary() }
        currentPage=page
        pageTitle.stringValue=page == .overview ? (controller.devicePlugin?.name ?? "Remote overview") : page.title
        pageSubtitle.stringValue=page.isRemoteScoped ? "\(controller.devicePlugin?.name ?? "Remote") · \(page == .buttons ? "App: " + (controller.appPlugin?.name ?? "No specific app") : page.subtitle)" : page.subtitle
        for (key,view) in pages { view.isHidden=key != page }
        sidebarNavigation.update(page:page,remoteName:remoteWorkspaceOpen ? controller.devicePlugin?.name ?? "Selected remote":nil)
        sidebarContext.stringValue=remoteWorkspaceOpen ? (currentPage == .voice ? "Microphone for this remote" : "Editing profile: \(controller.appPlugin?.name ?? "No specific app")") : "\(libraryDevices.count) \(libraryDevices.count == 1 ? "remote" : "remotes") · \(libraryConnectedCount) connected"
        if !sidebarNavigation.hasKeyboardFocus { window?.makeFirstResponder(nil) }
        refresh()
    }
    @objc private func navigateMenu(_ sender:NSMenuItem) { if let page=WorkspacePage.allCases.first(where:{$0.index == sender.tag}) { showPage(page) } }
    @objc private func openButtons() { showPage(.buttons) }
    @objc private func openVoice() { showPage(.voice) }
    @objc private func openApps() { showPage(.apps) }
    @objc private func openDevices() { showPage(.devices) }
    @objc private func openMicrophoneButton() { if let index=controller.microphoneIndex { selectedIndex=index };showPage(.buttons);refresh() }
    @objc private func overviewNext() {
        if !controller.config.remoteSetupCompleted { quickSetup() }
        else if !controller.running || controller.connected == 0 || !RemoteInput.allowed || !TargetOutput.allowed { showPage(.devices) }
        else { showPage(.buttons) }
    }
    @objc private func openPluginFolder() { do { try FileManager.default.createDirectory(at:sessions.pluginDirectory,withIntermediateDirectories:true);NSWorkspace.shared.open(sessions.pluginDirectory) } catch { show(error) } }
    @objc private func reloadPlugins() {
        guard confirmVoiceDraft() else { return }
        do {
            let selectedID=controller.config.devicePluginID
            try sessions.reload()
            pluginListSignature=""
            if let selected=sessions.controllers[selectedID] ?? sessions.initial { controller=selected }
            else { remoteWorkspaceOpen=false }
            selectedIndex=0;populatePlugins();loadEditable();showPage(remoteWorkspaceOpen ? currentPage:.remotes);refresh()
        } catch { show(error) }
    }
    @objc private func saveBehavior() { var config=controller.config;config.suppressOriginal=suppress.state == .on;do { try controller.update(config);refresh() } catch { show(error) } }

    private func label(_ text:String,size:CGFloat,weight:NSFont.Weight = .regular,color:NSColor = .rvInk)->NSTextField { let value=NSTextField(labelWithString:text);value.font = .systemFont(ofSize:size,weight:weight);value.textColor=color;return value }
    private func vertical(spacing:CGFloat)->NSStackView { let view=NSStackView();view.orientation = .vertical;view.alignment = .leading;view.spacing=spacing;return view }
    private func horizontal(_ views:[NSView],spacing:CGFloat)->NSStackView { let view=NSStackView(views:views);view.spacing=spacing;view.alignment = .centerY;return view }
    private func spacer()->NSView { let view=NSView();view.setContentHuggingPriority(.init(1),for:.horizontal);return view }
    private func button(_ text:String,_ selector:Selector,primary:Bool=false)->NSButton { let value:NSButton=primary ? PrimaryButton(title:text,target:self,action:selector) : NSButton(title:text,target:self,action:selector);value.bezelStyle = .rounded;value.controlSize = .large;if primary { value.bezelColor = .rvAccent;value.contentTintColor = .white };return value }
    private func pin(_ child:NSView,to parent:NSView,top:CGFloat,left:CGFloat,right:CGFloat) { parent.addSubview(child);child.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:left),child.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-right),child.topAnchor.constraint(equalTo:parent.topAnchor,constant:top)]) }
    private func card(_ content:NSView,padding:CGFloat)->NSView { let view=WorkspaceSurface(.card);pin(content,to:view,top:padding,left:padding,right:padding);content.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-padding).isActive=true;return view }
    private func loadEditable() { shortcut.setShortcut(controller.config.shortcut);confirmed.state=controller.config.shortcutConfirmed ? .on:.off;toggle.state=controller.config.voiceMode == "toggle" ? .on:.off;suppress.state=controller.config.suppressOriginal ? .on:.off }
    private func refresh() {
        for session in sessions.controllers.values {
            session.setButtonTestMode(ButtonTestState.shouldEnable(
                buttonsPageVisible:currentPage == .buttons && remoteWorkspaceOpen && session === controller,
                appActive:NSApp.isActive,windowVisible:window?.isVisible == true,windowMiniaturized:window?.isMiniaturized == true))
        }
        guard controller.config.bindings.indices.contains(selectedIndex) else { selectedIndex=0;return }
        followApp.state=controller.config.followActiveApp ? .on:.off
        routeLabel.stringValue=controller.config.followActiveApp ? (controller.running ? controller.routingLabel : "Connect remote to follow active app") : "Use only the selected app’s mappings"
        let binding=controller.config.bindings[selectedIndex]
        let signature=controller.config.bindings.map { ($0.controlID ?? "")+$0.name }.joined(separator:"|")
        if signature != pickerSignature { bindingPicker.removeAllItems();bindingPicker.addItems(withTitles:controller.config.bindings.map(\.name));pickerSignature=signature }
        bindingPicker.selectItem(at:selectedIndex)
        linked.stringValue=binding.usage == nil ? "Not linked yet" : "Linked to your remote"
        linked.textColor=binding.usage == nil ? .rvMuted : .systemTeal
        let item=controller.remoteLayout.buttons.first { $0.id == binding.controlID }
        hint.stringValue=item?.hint ?? "Select a button on the remote, then link it to the matching physical button."
        let learning=controller.learningIndex == selectedIndex
        learnButton.title=learning ? "Press remote button…" : binding.usage == nil ? "Link button" : "Relink button"
        learnButton.isEnabled = !learning;cancelButton.isHidden = !learning
        learningHelp.stringValue=learning ? "Press only \(binding.name) on your physical remote. This link will apply to all apps for this remote." : binding.usage == nil ? "Choose Link physical button, then press this button on your remote. The link is shared across apps; each app keeps its own action." : "Linked for this remote. Relinking updates all its app profiles and keeps their actions separate."
        let dictationShortcut=ShortcutCapture.display(controller.config.shortcut)
        actionPicker.removeAllItems();actionPicker.addItems(withTitles:controller.availableActions.map { $0 == .dictate ? "Dictation · \(dictationShortcut)" : $0.title });actionPicker.selectItem(at:controller.availableActions.firstIndex(of:binding.action) ?? 0)
        actionHelp.stringValue=binding.action == .native ? "Outside test mode, keeps the remote’s normal behavior. Choose an action to personalize it." : binding.usage == nil ? "Action selected. Learn this button to activate the mapping." : binding.action == .backspace ? "Press to delete one character. Hold to keep deleting; release to stop. Keep the text box focused." : "Saved for \(controller.appPlugin?.name ?? "the shared profile"). Other app profiles keep their own actions."
        voiceSection.isHidden=binding.action != .dictate || controller.appPlugin?.app?.supports(.dictate) != true
        let appName=controller.appPlugin?.name ?? "App"
        let toggleShortcut=controller.appPlugin?.app?.actions["dictate"]?.operation == "toggle-shortcut"
        dictationBinding.stringValue=dictationShortcut.isEmpty ? "No shortcut set" : dictationShortcut
        dictationBinding.toolTip="Configured shortcut: \(controller.config.shortcut)"
        let behavior=toggleShortcut ? "Tap shortcut to start / stop" : "Hold shortcut while dictating"
        dictationBindingHelp.stringValue="\(appName) · \(behavior).\n" + (controller.config.shortcutConfirmed ? "Shortcut confirmed in voice settings." : "Needs confirmation in voice settings.")
        dictationBindingHelp.textColor=controller.config.shortcutConfirmed ? .rvMuted:.systemOrange
        if binding.action == .dictate {
            let gesture=controller.config.voiceMode == "toggle" ? "Press once to start, again to stop." : "Hold the remote button to dictate."
            actionHelp.stringValue="\(binding.name) → \(appName)\n\(gesture)"
        }
        learnButton.toolTip=learningHelp.stringValue
        bindingPicker.toolTip=hint.stringValue + (binding.usage.map { "\nButton signal: \($0.label)" } ?? "\nButton signal: not linked")
        if learning { linked.stringValue="Press this button on your remote";linked.textColor = .systemOrange }
        let noSpecificApp=controller.config.appPluginID == Configuration.noSpecificAppID
        followApp.isEnabled = true
        if noSpecificApp {
            if !controller.config.followActiveApp { routeLabel.stringValue="Shared controls only. Turn on Follow active app to use each app’s saved controls and dictation shortcut." }
            if binding.controlID == "microphone" {
                actionHelp.stringValue="Shared controls apply to other apps. With Follow active app on, supported apps use their saved dictation shortcut automatically."
            }
        }
        let layout=controller.remoteLayout
        canvas.update(layout:layout,bindings:controller.config.bindings,selection:binding.controlID ?? "button-\(selectedIndex)",active:controller.displayedUsages)
        let learningID=controller.learningIndex.map { controller.config.bindings[$0].controlID ?? "button-\($0)" }
        mappingBoard.update(layout:layout,bindings:controller.config.bindings,selection:binding.controlID ?? "button-\(selectedIndex)",actions:controller.availableActions,learningID:learningID,active:controller.displayedUsages,dictationShortcut:dictationShortcut)
        testConnectButton.title=controller.running ? "Disconnect":"Connect to test"
        buttonTestTitle.stringValue = !controller.running || controller.connected == 0 ? "TEST MODE · Connect your remote to start" : controller.buttonTestMode ? "TEST MODE · App actions paused":"TEST MODE · Paused while using another app"
        if !controller.running { buttonTestStatus.stringValue="Connect your remote to test. " + controller.status }
        else if controller.connected == 0 { buttonTestStatus.stringValue="Waiting for the remote’s receiver. App actions are paused." }
        else if let failure=controller.buttonTestFailure {
            buttonTestTitle.stringValue="Button test unavailable · Remote connected"
            buttonTestStatus.stringValue="Normal remote actions remain active. " + failure
        }
        else if !controller.buttonTestMode { buttonTestStatus.stringValue="Normal remote actions are active. Return to this window to test without sending actions." }
        else if let usage=controller.buttonTest.lastUsage {
            let name=controller.config.bindings.first(where: { $0.usage == usage })?.name
            buttonTestStatus.stringValue=name.map { "\($0) detected · no action sent" } ?? "Unlinked button detected (\(usage.label)) · select its button and choose Link."
        } else { buttonTestStatus.stringValue="Press any remote button. It will light up without sending keys or starting dictation." }
        let linkedCount=layout.buttons.filter { item in controller.config.bindings.contains { $0.controlID == item.id && $0.usage != nil } }.count
        progress.stringValue="\(linkedCount) of \(layout.buttons.count) buttons linked"
        badge.stringValue=controller.running ? controller.connected > 0 ? "  Connected  " : "  Looking for remote…  " : "  Not connected  "
        badge.textColor=controller.connected > 0 ? .systemTeal:.rvMuted
        connectButton.title=controller.running ? "Disconnect" : "Connect remote"
        sidebarNavigation.update(page:currentPage,remoteName:remoteWorkspaceOpen ? controller.devicePlugin?.name ?? "Selected remote":nil)
        sidebarContext.stringValue=remoteWorkspaceOpen ? (currentPage == .voice ? "Microphone for this remote" : "Editing profile: \(controller.appPlugin?.name ?? "No specific app")") : "\(libraryDevices.count) \(libraryDevices.count == 1 ? "remote" : "remotes") · \(libraryConnectedCount) connected"
        if currentPage.isRemoteScoped {
            pageTitle.stringValue=currentPage == .overview ? (controller.devicePlugin?.name ?? "Remote overview") : currentPage.title
            pageSubtitle.stringValue="\(controller.devicePlugin?.name ?? "Remote") · \(currentPage == .buttons ? "App: " + (controller.appPlugin?.name ?? "No specific app") : currentPage.subtitle)"
        }
        rebuildRemoteLibrary()
        remoteArtworkPreview.reference=controller.artwork.image;remoteArtworkPreview.remoteLayout=controller.devicePlugin?.device?.layout
        overviewArtwork.reference=controller.artwork.image;overviewArtwork.remoteLayout=controller.devicePlugin?.device?.layout
        artworkStatus.stringValue=controller.artwork.image != nil ? "Your image · saved for this remote":controller.devicePlugin?.device?.layout != nil ? "Remote design · from its plugin":"Generic remote illustration"
        resetArtworkButton.isEnabled=controller.artwork.image != nil
        resetArtworkButton.title=controller.devicePlugin?.device?.layout != nil ? "Use remote design":"Use generic artwork"
        overviewConnection.stringValue=controller.running && controller.connected > 0 ? "Connected · \(controller.devicePlugin?.name ?? "remote")" : "Not connected · choose a device and connect"
        overviewApp.stringValue=noSpecificApp ? (controller.config.followActiveApp ? "Automatic app controls · editing shared fallback":"Shared controls only") : "Editing \(controller.appPlugin?.name ?? "no app") · \(controller.config.followActiveApp ? "Follows the active app":"Uses selected profile")"
        overviewVoice.stringValue=controller.appPlugin?.app?.supports(.dictate) == true ? (controller.config.dictationTested ? "Setup test confirmed · review microphone and shortcut":"Setup needs a microphone, shortcut, and test") : noSpecificApp && controller.config.followActiveApp ? "Uses each active app’s saved dictation shortcut":"The selected app plugin does not provide dictation"
        let toggledShortcut=controller.appPlugin?.app?.actions["dictate"]?.operation == "toggle-shortcut"
        confirmed.title=toggledShortcut ? "Matches my app’s start/stop dictation shortcut":"Matches my app’s hold-to-dictate shortcut"
        rebuildPluginList()
        rebuildSupportedApps()
        populatePlugins()
        refreshVoiceTests()
        status.isHidden=currentPage == .voice
        let connected=controller.running && controller.connected>0
        let permissions=RemoteInput.allowed && TargetOutput.allowed
        let ready=controller.config.remoteSetupCompleted && connected && permissions
        overviewTitle.stringValue = !controller.config.remoteSetupCompleted ? "Let’s set up this remote" : !permissions ? "Allow your remote to work with apps" : !connected ? "Connect your remote" : "Your remote is ready to use"
        overviewDetail.stringValue = !controller.config.remoteSetupCompleted ? "A short welcome guide takes you from choosing an app to trying your first action. Continue from where you left off." : ready ? "Open your app and try a linked button. Customize more buttons whenever you need them." : "Your setup is saved. Review this remote’s connection and permissions to use it again."
        overviewAction.title = !controller.config.remoteSetupCompleted ? "Continue setup" : ready ? "Customize buttons":"Review connection"
        if controller.config.remoteSetupCompleted && controller.config.remoteSetupCheckpoint?.wantsVoice == false {
            overviewVoice.stringValue="Optional · add voice whenever you need it"
        }
        voiceStop.isHidden = !sessions.voiceActive
        if currentPage.isRemoteScoped {
            status.stringValue=currentPage == .buttons && controller.running && controller.buttonTestFailure != nil ? "Remote connected · Button testing unavailable. Normal remote actions remain active." : currentPage == .buttons ? (controller.buttonTestMode ? "Test mode · switch to your app to resume normal remote actions. ":"Test mode paused · \(controller.routingLabel). ") + (controller.running ? "":controller.status) : controller.status.hasPrefix("Connected ·") ? "Remote connected · \(controller.routingLabel)" : (controller.status.hasPrefix("Learned ") ? "\(binding.name) linked. Choose what it does above." : controller.status)
        } else {
            let connected=libraryConnectedCount
            status.stringValue=libraryDevices.isEmpty ? "Add your first remote to get started.":"\(connected) \(connected == 1 ? "remote" : "remotes") connected. Each remote keeps its own settings."
        }
    }
    private func selectControl(_ id:String) { if let index=controller.config.bindings.firstIndex(where:{$0.controlID == id}) { selectedIndex=index } else if id.hasPrefix("button-"),let index=Int(id.dropFirst(7)) { selectedIndex=index };if controller.learningIndex != nil { controller.cancelLearning() };refresh() }
    @objc private func pickBinding() { selectedIndex=bindingPicker.indexOfSelectedItem;controller.cancelLearning();refresh() }
    @objc private func checkConnection() {
        guard connectionWindow == nil else{return};let check=ConnectionCheck(controller:controller,parent:window);connectionWindow=check
        check.finished={ [weak self] in self?.connectionWindow=nil;self?.refresh() };check.show()
    }
    @objc private func chooseArtwork() {
        let picker=NSOpenPanel();picker.allowedContentTypes=[.png,.jpeg,.heic];picker.allowsMultipleSelection=false
        picker.message="Choose a photo or illustration for this remote."
        if picker.runModal() == .OK,let url=picker.url { do { try controller.setArtwork(from:url) } catch { show(error) } }
    }
    @objc private func resetArtwork() { do { try controller.resetArtwork() } catch { show(error) } }
    @objc private func setupCursor() {
        guard cursorWindow == nil else { return };let setup=CursorSetup(controller:controller,parent:window);cursorWindow=setup
        setup.finished={ [weak self] in self?.cursorWindow=nil;self?.refresh() };setup.show()
    }
    @objc private func testMicrophone() {
        guard microphoneWindow == nil else { return }
        let test=MicrophoneTest(controller:controller,parent:window); microphoneWindow=test
        test.finished={ [weak self] in self?.microphoneWindow=nil;self?.refresh() };test.show()
    }
    @objc private func quickSetup() {
        guard remoteWorkspaceOpen else { showPage(.remotes);return }
        guard setupWizard == nil,confirmVoiceDraft() else { return }
        let setup=QuickSetup(controller:controller,parent:window)
        setupWizard=setup
        setup.finished={ [weak self] in self?.setupWizard=nil;self?.loadEditable();self?.refresh() }
        setup.show()
    }
    @objc private func connect() { if controller.running { do { try controller.stop() } catch { show(error) } } else { controller.start() } }
    @objc private func learn() { if !controller.running { controller.start() };if controller.running { controller.learn(selectedIndex) } }
    @objc private func cancelLearning() { controller.cancelLearning() }
    @objc private func changeRouting() { var config=controller.config; config.followActiveApp=followApp.state == .on; do { try controller.update(config) } catch { show(error); refresh() } }
    @objc private func changeAction() { guard actionPicker.indexOfSelectedItem >= 0 else { return };var config=controller.config;config.bindings[selectedIndex].action=controller.availableActions[actionPicker.indexOfSelectedItem];do { try controller.update(config) } catch { show(error) } }
    @objc private func saveVoice() { _ = saveVoiceSettings() }
    private func saveVoiceSettings() -> Bool { var config=controller.config;config.shortcut=shortcut.shortcutValue ?? "";config.shortcutConfirmed=confirmed.state == .on;config.voiceMode=toggle.state == .on ? "toggle":"hold";do { try controller.update(config); return true } catch { show(error);return false } }
    @objc private func stopVoice() { sessions.stopVoices() }
    private func populatePlugins() {
        var choices=[AppIconChoice(id:Configuration.noSpecificAppID,name:"No specific app",image:NSImage(systemSymbolName:"square.dashed",accessibilityDescription:nil))]
        for plugin in sessions.catalog.apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let configured=plugin.id == controller.config.appPluginID ? controller.config.targetAppPath : controller.config.appMappings[AppRouting.key(controller.config.devicePluginID,plugin.id)]?.targetAppPath ?? ""
            let url = !configured.isEmpty ? URL(fileURLWithPath:configured) : plugin.app?.targets["macos"]?.bundleIds.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }.first
            choices.append(AppIconChoice(id:plugin.id,name:plugin.name,image:url.map { NSWorkspace.shared.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"app.fill",accessibilityDescription:nil)))
        }
        appIconSelector.update(choices:choices,selection:controller.config.appPluginID)
    }
    private var voiceDraftChanged: Bool {
        (shortcut.shortcutValue ?? "") != controller.config.shortcut || (confirmed.state == .on) != controller.config.shortcutConfirmed || (toggle.state == .on) != (controller.config.voiceMode == "toggle")
    }
    private func selectAppProfile(_ appID:String) {
        guard appID != controller.config.appPluginID,confirmVoiceDraft() else { populatePlugins();return }
        do {
            try controller.selectPlugins(deviceID:controller.config.devicePluginID,appID:appID)
            selectedIndex=0;loadEditable();populatePlugins();refresh()
        } catch { show(error);populatePlugins() }
    }
    private func confirmVoiceDraft() -> Bool {
        guard voiceDraftChanged else { return true }
        let alert=NSAlert();alert.messageText="Save your voice settings?";alert.informativeText="You have unsaved voice changes for the current app profile."
        alert.addButton(withTitle:"Save changes");alert.addButton(withTitle:"Discard changes");alert.addButton(withTitle:"Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveVoiceSettings()
        case .alertSecondButtonReturn: loadEditable();return true
        default: return false
        }
    }
    func windowShouldClose(_ sender:NSWindow) -> Bool { guard confirmVoiceDraft() else { return false };clearVoiceMicrophoneTest();return true }
    @objc private func addApplication() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.application];panel.allowsMultipleSelection=false
        panel.canChooseDirectories=false;panel.treatsFilePackagesAsDirectories=false
        panel.directoryURL=URL(fileURLWithPath:"/Applications");panel.prompt="Choose app";panel.message="Choose an application to control with this remote."
        panel.beginSheetModal(for:window) { [weak self] response in
            if response == .OK,let url=panel.url { self?.addDroppedApplication(at:url) }
        }
    }
    private func addDroppedApplication(at url:URL) {
        guard confirmVoiceDraft() else { return }
        do {
            let application=try LocalAppRegistration(url:url)
            let existing=sessions.catalog.apps.filter { $0.app?.targets["macos"]?.bundleIds.contains(application.bundleID) == true }
            if !existing.isEmpty {
                let plugin=try sessions.addApp(application)
                try selectAddedApplication(plugin,url:application.url)
                return
            }
            let alert=NSAlert();alert.messageText="Add \(application.name)?"
            alert.informativeText="Create a profile for this app with Open app, Return, Backspace, and Escape actions. You can assign them to remote buttons next."
            alert.icon=NSWorkspace.shared.icon(forFile:application.url.path)
            alert.addButton(withTitle:"Add app");alert.addButton(withTitle:"Cancel")
            let options=NSView(frame:NSRect(x:0,y:0,width:420,height:112))
            let voice=NSButton(checkboxWithTitle:"This app supports a held dictation shortcut",target:nil,action:nil)
            voice.frame=NSRect(x:0,y:86,width:420,height:22)
            let keys=ShortcutRecorder(frame:NSRect(x:0,y:46,width:420,height:32))
            keys.setAccessibilityLabel("App’s verified hold-to-dictate shortcut")
            keys.changed={ [weak keys,weak voice,weak submit=alert.buttons.first] in
                submit?.isEnabled = voice?.state != .on || keys?.shortcutValue != nil
            }
            voice.target=keys;voice.action=#selector(ShortcutRecorder.optionChanged(_:))
            let note=NSTextField(wrappingLabelWithString:"Click to record, then press your app’s shortcut. Esc cancels. Use a letter, Space, Return, Backspace, or Escape with any modifiers.")
            note.frame=NSRect(x:0,y:0,width:420,height:40);note.font = .systemFont(ofSize:11);note.textColor = .rvMuted
            [voice,keys,note].forEach { options.addSubview($0) };alert.accessoryView=options
            alert.beginSheetModal(for:window) { [weak self] response in
                guard let self,response == .alertFirstButtonReturn else { return }
                do {
                    let plugin=try self.sessions.addApp(application,dictationShortcut:voice.state == .on ? keys.shortcutValue ?? "":nil)
                    try self.selectAddedApplication(plugin,url:application.url)
                } catch { self.show(error) }
            }
        } catch { show(error) }
    }
    private func selectAddedApplication(_ plugin:PluginManifest,url:URL) throws {
        let config=try LocalAppRegistration.selecting(plugin,url:url,config:controller.config,catalog:controller.catalog)
        try controller.update(config)
        selectedIndex=0;populatePlugins();loadEditable();refresh()
        showPage(.buttons)
        status.stringValue="\(plugin.name) is ready. Choose a button to assign its action."
    }
    private func show(_ error:Error) { let alert=NSAlert();alert.messageText="JustVibe Remote";alert.informativeText=error.localizedDescription;alert.runModal() }
    // The editor is a test surface only while JustVibe Remote is being used.
    // Keeping it open behind the target app must never suppress dictation.
    private func refreshInputFocus() { guard sessions != nil,controller != nil,testConnectButton != nil else { return };refresh() }
    func applicationDidBecomeActive(_ notification:Notification) { refreshInputFocus() }
    func applicationDidResignActive(_ notification:Notification) { refreshInputFocus() }
    func applicationDidHide(_ notification:Notification) { refreshInputFocus() }
    func applicationDidUnhide(_ notification:Notification) { refreshInputFocus() }
    func windowDidMiniaturize(_ notification:Notification) { refreshInputFocus() }
    func windowDidDeminiaturize(_ notification:Notification) { refreshInputFocus() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply { guard controller != nil else { return .terminateNow };guard confirmVoiceDraft() else { return .terminateCancel };clearVoiceMicrophoneTest();do { try sessions.shutdown();return .terminateNow } catch { show(error);return .terminateCancel } }
}
extension NSBox { static func separator()->NSBox { let value=NSBox();value.boxType = .separator;return value } }
let application=NSApplication.shared
let delegate=AppDelegate()
application.delegate=delegate
if CommandLine.arguments.contains("--render-add-remote-preview") || CommandLine.arguments.contains("--dictation-button-diagnostics") || CommandLine.arguments.contains("--render-cursor-preview") || CommandLine.arguments.contains("--render-connection-preview") || CommandLine.arguments.contains("--list-audio-inputs") || CommandLine.arguments.contains("--render-microphone-preview") || CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--render-setup-preview") { delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification)) } else { application.run() }

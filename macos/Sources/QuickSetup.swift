import AppKit
import UniformTypeIdentifiers

/// A focused, resumable journey for one remote. Polling updates visible status;
/// learning, permissions, capture, and completion always require user actions.
final class QuickSetup: NSObject, NSWindowDelegate {
    private let controller: RemoteController
    private weak var parent: NSWindow?
    private let panel: NSPanel
    private var checkpoint: RemoteSetupCheckpoint
    private let wasRunning: Bool
    private var ended=false
    private var timer: Timer?
    private var connectionCheck: ConnectionCheck?
    private var audioTest: SetupMicrophoneTest?
    private let body=NSStackView(), visual=NSStackView(), milestones=NSStackView()
    private let stageLabel=NSTextField(labelWithString:"")
    private let heading=NSTextField(wrappingLabelWithString:"")
    private let lead=NSTextField(wrappingLabelWithString:"")
    private let feedback=NSTextField(wrappingLabelWithString:"")
    private let content=NSStackView()
    private let canvas=RemoteCanvas()
    private let remoteArtwork=RemoteArtworkView(frame:.zero)
    private let illustration=NSImageView()
    private let checkmarkArtwork=SetupCheckmarkArtwork(frame:.zero)
    private var previewPermissionCount:Int?
    private let visualCaption=NSTextField(wrappingLabelWithString:"")
    private let appPicker=NSPopUpButton(),buttonPicker=NSPopUpButton(),actionPicker=NSPopUpButton(),micPicker=NSPopUpButton()
    private let shortcut=ShortcutRecorder(frame:.zero)
    private let voiceChoice=NSButton(checkboxWithTitle:"Set up voice input too (optional)",target:nil,action:nil)
    private let toggle=NSButton(checkboxWithTitle:"Press once to start voice, again to stop",target:nil,action:nil)
    private let reconnect=NSButton(checkboxWithTitle:"Connect this remote automatically when I open JustVibe Remote",target:nil,action:nil)
    private var primary:NSButton!,back:NSButton!,later:NSButton!
    private var receiverConnectButton:NSButton?,receiverHelpButton:NSButton?
    private var inputs:[AudioInput]=[]
    private var selectedIndex:Int
    private var visibleStage:RemoteSetupStage?
    private var learningLink:NSButton?,learningCancel:NSButton?
    private var inputPermissionRow:SetupChecklistRow?,shortcutPermissionRow:SetupChecklistRow?
    private var microphoneHelp=NSTextField(wrappingLabelWithString:"")
    private var microphoneDefaultButton:NSButton?
    private var microphoneButtonHint:NSTextField?,microphoneLockedHint:NSTextField?
    private var microphoneButtonStep:VoiceSetupStepView?,microphoneInputStep:VoiceSetupStepView?
    private var microphoneControls:NSStackView?
    private var milestoneRows:[SetupMilestoneView]=[]
    private var setupActions:[RemoteAction] { controller.availableActions.filter { $0 != .dictate } }
    private var suggestedShortcut:String? { try? controller.appPlugin?.app?.shortcut(.dictate) }
    private var initialShortcut:String { SetupShortcut.initialValue(saved:controller.config.shortcut,confirmed:controller.config.shortcutConfirmed,suggested:suggestedShortcut) }
    var finished:(() -> Void)?

    init(controller: RemoteController, parent: NSWindow) {
        self.controller=controller;self.parent=parent;wasRunning=controller.running
        let saved=controller.config.remoteSetupCheckpoint
        checkpoint=saved?.stage != .done ? saved ?? RemoteSetupCheckpoint() : RemoteSetupCheckpoint()
        if controller.appPlugin?.app?.supports(.dictate) != true { checkpoint.wantsVoice=false }
        checkpoint=checkpoint.resuming(appAvailable:controller.appPlugin != nil,inputAllowed:RemoteInput.allowed,shortcutsAllowed:TargetOutput.allowed,connected:controller.running && controller.connected>0)
        selectedIndex=checkpoint.controlID.flatMap { id in controller.config.bindings.firstIndex { $0.controlID == id } }
            ?? controller.config.bindings.firstIndex { $0.controlID == "ok" || $0.name == "OK" }
            ?? controller.config.bindings.firstIndex { $0.controlID != "microphone" } ?? 0
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:940,height:680),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init()
        panel.title="Set up \(controller.devicePlugin?.name ?? "your remote")";panel.delegate=self;panel.isReleasedWhenClosed=false;panel.appearance=NSAppearance(named:.aqua)
        build()
        shortcut.setShortcut(initialShortcut)
        shortcut.changed={ [weak self] in self?.refresh() }
        toggle.state=controller.config.voiceMode == "toggle" ? .on:.off
        reconnect.state=controller.config.autoConnect ? .on:.off
        voiceChoice.state=checkpoint.wantsVoice ? .on:.off
        refresh()
    }
    private func text(_ value:String,size:CGFloat=13,weight:NSFont.Weight = .regular,color:NSColor = .rvInk)->NSTextField {
        let field=NSTextField(wrappingLabelWithString:value);field.font = .systemFont(ofSize:size,weight:weight);field.textColor=color
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);return field
    }
    private func vertical(_ stack:NSStackView,spacing:CGFloat=14) { stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=spacing }
    private func button(_ title:String,_ selector:Selector)->NSButton { let value=NSButton(title:title,target:self,action:selector);value.bezelStyle = .rounded;value.controlSize = .large;return value }
    private func build() {
        let root=WorkspaceSurface(.card);panel.contentView=root
        let picture=WorkspaceSurface(.sidebar)
        root.addSubview(picture);picture.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([picture.leadingAnchor.constraint(equalTo:root.leadingAnchor),picture.topAnchor.constraint(equalTo:root.topAnchor),picture.bottomAnchor.constraint(equalTo:root.bottomAnchor),picture.widthAnchor.constraint(equalToConstant:300)])
        vertical(visual,spacing:12);picture.addSubview(visual);visual.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([visual.leadingAnchor.constraint(equalTo:picture.leadingAnchor,constant:26),visual.trailingAnchor.constraint(equalTo:picture.trailingAnchor,constant:-26),visual.topAnchor.constraint(equalTo:picture.topAnchor,constant:28)])
        visual.addArrangedSubview(text("REMOTE SETUP",size:10,weight:.semibold,color:.rvAccent))
        let remoteName=text(controller.devicePlugin?.name ?? "Your remote",size:19,weight:.semibold);remoteName.maximumNumberOfLines=2;visual.addArrangedSubview(remoteName)
        let art=NSView();visual.addArrangedSubview(art);art.translatesAutoresizingMaskIntoConstraints=false
        art.widthAnchor.constraint(equalTo:visual.widthAnchor).isActive=true;art.heightAnchor.constraint(equalToConstant:350).isActive=true
        art.addSubview(canvas);canvas.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([canvas.leadingAnchor.constraint(equalTo:art.leadingAnchor),canvas.trailingAnchor.constraint(equalTo:art.trailingAnchor),canvas.topAnchor.constraint(equalTo:art.topAnchor),canvas.bottomAnchor.constraint(equalTo:art.bottomAnchor)])
        art.addSubview(remoteArtwork);remoteArtwork.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([remoteArtwork.leadingAnchor.constraint(equalTo:art.leadingAnchor),remoteArtwork.trailingAnchor.constraint(equalTo:art.trailingAnchor),remoteArtwork.topAnchor.constraint(equalTo:art.topAnchor),remoteArtwork.bottomAnchor.constraint(equalTo:art.bottomAnchor)])
        art.addSubview(illustration);illustration.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([illustration.centerXAnchor.constraint(equalTo:art.centerXAnchor),illustration.centerYAnchor.constraint(equalTo:art.centerYAnchor),illustration.widthAnchor.constraint(equalToConstant:150),illustration.heightAnchor.constraint(equalToConstant:170)])
        art.addSubview(checkmarkArtwork);checkmarkArtwork.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([checkmarkArtwork.centerXAnchor.constraint(equalTo:art.centerXAnchor),checkmarkArtwork.centerYAnchor.constraint(equalTo:art.centerYAnchor),checkmarkArtwork.widthAnchor.constraint(equalToConstant:230),checkmarkArtwork.heightAnchor.constraint(equalToConstant:250)])
        illustration.imageScaling = .scaleProportionallyUpOrDown;illustration.contentTintColor = .rvAccent
        canvas.selected={ [weak self] id in
            guard let self,self.checkpoint.stage == .button,let index=self.controller.config.bindings.firstIndex(where:{$0.controlID == id}) else { return }
            self.controller.cancelLearning();self.selectedIndex=index;self.checkpoint.controlID=id;self.rebuildContent();self.refresh()
        }
        visualCaption.font = .systemFont(ofSize:12);visualCaption.textColor = .rvMuted;visualCaption.alignment = .center;visual.addArrangedSubview(visualCaption)
        vertical(milestones,spacing:9);picture.addSubview(milestones);milestones.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([milestones.leadingAnchor.constraint(equalTo:picture.leadingAnchor,constant:28),milestones.trailingAnchor.constraint(equalTo:picture.trailingAnchor,constant:-22),milestones.bottomAnchor.constraint(equalTo:picture.bottomAnchor,constant:-26)])
        for name in ["Welcome","Choose an app","Connect","Set up controls","Try it"] {
            let row=SetupMilestoneView(title:name);milestones.addArrangedSubview(row);milestoneRows.append(row)
        }
        let footer=NSStackView();footer.spacing=10
        back=button("Back",#selector(goBack));primary=PrimaryButton(title:"Get started",target:self,action:#selector(advance));primary.isBordered=false
        later=button("Continue later",#selector(cancel));later.keyEquivalent="\u{1b}"
        let space=NSView();space.setContentHuggingPriority(.init(1),for:.horizontal)
        [back,later,space,primary].forEach { footer.addArrangedSubview($0) }
        root.addSubview(footer);footer.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo:picture.trailingAnchor,constant:30),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-30),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-25),footer.heightAnchor.constraint(equalToConstant:38)])
        let scroll=NSScrollView();scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;root.addSubview(scroll);scroll.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:picture.trailingAnchor,constant:30),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-30),scroll.topAnchor.constraint(equalTo:root.topAnchor,constant:28),scroll.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-18)])
        let document=WorkspaceDocument();document.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=document
        vertical(body,spacing:16);document.addSubview(body);body.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),body.leadingAnchor.constraint(equalTo:document.leadingAnchor),body.trailingAnchor.constraint(equalTo:document.trailingAnchor),body.topAnchor.constraint(equalTo:document.topAnchor),body.bottomAnchor.constraint(equalTo:document.bottomAnchor)])
        stageLabel.font = .systemFont(ofSize:11,weight:.semibold);stageLabel.textColor = .rvAccent
        heading.font = .systemFont(ofSize:28,weight:.bold);heading.textColor = .rvInk
        lead.font = .systemFont(ofSize:14);lead.textColor = .rvMuted
        feedback.font = .systemFont(ofSize:12);feedback.textColor = .rvMuted
        vertical(content,spacing:14)
        for view in [stageLabel,heading,lead,content,feedback] { body.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:body.widthAnchor).isActive=true }
    }
    func show() {
        guard let parent else { return };controller.stopVoice();parent.beginSheet(panel)
        timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.refresh() }
    }
    private func add(_ view:NSView) { content.addArrangedSubview(view);view.widthAnchor.constraint(lessThanOrEqualTo:content.widthAnchor).isActive=true }
    private func note(_ value:String) { add(text(value,size:12,color:.rvMuted)) }
    private func clearContent() { audioTest?.close();audioTest=nil;for view in content.arrangedSubviews { content.removeArrangedSubview(view);view.removeFromSuperview() } }
    private func rebuildContent() {
        visibleStage=checkpoint.stage;clearContent();feedback.stringValue=""
        let app=controller.appPlugin?.name ?? "your app"
        switch checkpoint.stage {
        case .welcome:
            heading.stringValue="Make this remote yours."
            lead.stringValue="Pick an app, link a button, and try your first action. We’ll guide you through it one step at a time."
            add(text("Your apps, one press away",size:16,weight:.semibold));note("Give buttons useful actions, like showing an app, sending text, or deleting a character.")
            add(text("Voice, if you want it",size:16,weight:.semibold));note("Add the remote’s microphone when you’re ready. Buttons work without voice setup.")
            add(text("Pick up where you left off",size:16,weight:.semibold));note("Your choices are saved as you go. You can continue later.")
            add(button("Use a photo of your remote…",#selector(chooseRemoteArtwork)))
        case .app:
            heading.stringValue="Where will you use it?";lead.stringValue="Choose the first app for this remote. You can add more app profiles afterward."
            appPicker.removeAllItems();for plugin in controller.catalog.apps { appPicker.addItem(withTitle:plugin.name);appPicker.lastItem?.representedObject=plugin.id }
            if let index=appPicker.itemArray.firstIndex(where:{($0.representedObject as? String) == controller.config.appPluginID}) { appPicker.selectItem(at:index) }
            appPicker.target=self;appPicker.action=#selector(changeApp);appPicker.setAccessibilityLabel("First app for this remote");add(appPicker)
            voiceChoice.target=self;voiceChoice.action=#selector(changeVoiceChoice);voiceChoice.isEnabled=controller.appPlugin?.app?.supports(.dictate) == true;add(voiceChoice)
            note(voiceChoice.isEnabled ? "Voice setup adds a microphone check and a matching dictation shortcut." : "This app plugin provides button actions. Voice setup is not needed.")
        case .permissions:
            heading.stringValue="Let your remote work with apps.";lead.stringValue="macOS needs two permissions. Open each setting, switch on JustVibe Remote, then come back here."
            inputPermissionRow=SetupChecklistRow(title:"Input Monitoring",detail:"Read buttons from your remote.",actionTitle:"Allow access",target:self,selector:#selector(allowInput))
            shortcutPermissionRow=SetupChecklistRow(title:"Accessibility",detail:"Send your chosen actions to apps.",actionTitle:"Allow access",target:self,selector:#selector(allowShortcuts))
            for row in [inputPermissionRow!,shortcutPermissionRow!] { add(row);row.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true }
            add(button("Having trouble? Check connection…",#selector(checkConnection)))
        case .receiver:
            heading.stringValue="Connect your remote.";lead.stringValue="Plug in the USB receiver or pair \(controller.config.profile.name) in macOS Bluetooth settings. Then connect it below."
            receiverConnectButton=button("Connect this remote",#selector(connect));add(receiverConnectButton!)
            receiverHelpButton=button("Connection help…",#selector(checkConnection));add(receiverHelpButton!)
        case .button:
            heading.stringValue="Make the buttons yours.";lead.stringValue="Keep the existing controls and continue, or choose a button to customize for \(app). You can change buttons later in remote settings."
            buttonPicker.removeAllItems();buttonPicker.addItems(withTitles:controller.config.bindings.map(\.name));buttonPicker.selectItem(at:selectedIndex)
            buttonPicker.target=self;buttonPicker.action=#selector(changeButton);buttonPicker.setAccessibilityLabel("Button to set up");add(buttonPicker)
            learningLink=button("Link this button",#selector(learnButton));learningCancel=button("Cancel learning",#selector(cancelLearning));add(learningLink!);add(learningCancel!)
            actionPicker.removeAllItems();actionPicker.addItem(withTitle:"Choose an action…");actionPicker.addItems(withTitles:setupActions.map(\.title));actionPicker.selectItem(at:setupActions.firstIndex(of:controller.config.bindings[selectedIndex].action).map { $0+1 } ?? 0)
            actionPicker.target=self;actionPicker.action=#selector(changeAction);actionPicker.setAccessibilityLabel("Action for this button");add(text("In \(app), this button will…",size:13,weight:.semibold));add(actionPicker)
            note("Linking identifies the button. It won’t run its assigned action while learning.")
        case .microphone:
            heading.stringValue="Add voice to your remote.";lead.stringValue="Set up a button for dictation in \(app), then check your remote’s microphone."
            let buttonStep=VoiceSetupStepView(number:1,title:"Dictation button");microphoneButtonStep=buttonStep;add(buttonStep)
            buttonStep.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true
            let buttonHint=text("",size:13,color:.rvMuted);microphoneButtonHint=buttonHint;buttonStep.content.addArrangedSubview(buttonHint)
            buttonHint.widthAnchor.constraint(equalTo:buttonStep.content.widthAnchor).isActive=true
            learningLink=button("Set up button",#selector(learnMicrophone));learningCancel=button("Cancel",#selector(cancelLearning))
            let linking=NSStackView(views:[learningLink!,learningCancel!]);linking.spacing=8;buttonStep.content.addArrangedSubview(linking)
            let inputStep=VoiceSetupStepView(number:2,title:"Microphone");microphoneInputStep=inputStep;add(inputStep)
            inputStep.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true
            let lockedHint=text("Next, choose the remote’s microphone and check your voice with a short test.",size:13,color:.rvMuted);microphoneLockedHint=lockedHint;inputStep.content.addArrangedSubview(lockedHint)
            lockedHint.widthAnchor.constraint(equalTo:inputStep.content.widthAnchor).isActive=true
            let controls=NSStackView();vertical(controls,spacing:12);microphoneControls=controls;inputStep.content.addArrangedSubview(controls)
            controls.widthAnchor.constraint(equalTo:inputStep.content.widthAnchor).isActive=true
            let inputHint=text("Choose the remote’s USB microphone. You can record a short clip and play it back to check your voice.",size:12,color:.rvMuted)
            controls.addArrangedSubview(inputHint);inputHint.widthAnchor.constraint(equalTo:controls.widthAnchor).isActive=true
            inputs=AudioInputs.list();micPicker.removeAllItems();micPicker.addItem(withTitle:"Choose the remote’s microphone…")
            for input in inputs { micPicker.addItem(withTitle:input.name + (input.usb ? " · USB":"")) }
            if let saved=controller.config.microphones[controller.config.devicePluginID],let index=inputs.firstIndex(where:{$0.id == saved.id}) { micPicker.selectItem(at:index+1) }
            micPicker.setAccessibilityLabel("Remote USB microphone");micPicker.target=self;micPicker.action=#selector(changeMicrophone);controls.addArrangedSubview(micPicker)
            let test=SetupMicrophoneTest(controller:controller);audioTest=test;controls.addArrangedSubview(test)
            test.widthAnchor.constraint(equalTo:controls.widthAnchor).isActive=true;changeMicrophone()
            microphoneHelp.font = .systemFont(ofSize:12);microphoneHelp.textColor = .rvMuted;controls.addArrangedSubview(microphoneHelp)
            microphoneHelp.widthAnchor.constraint(equalTo:controls.widthAnchor).isActive=true
            microphoneDefaultButton=button("Use selected microphone as system input",#selector(useSelectedMicrophone));controls.addArrangedSubview(microphoneDefaultButton!)
            let appHint=text("Select the same microphone in \(app)’s settings.",size:12,color:.rvMuted);controls.addArrangedSubview(appHint)
            appHint.widthAnchor.constraint(equalTo:controls.widthAnchor).isActive=true
            let optionalHint=text("The audio test is optional. Click Continue when you’re ready.",size:12,color:.rvMuted);controls.addArrangedSubview(optionalHint)
            optionalHint.widthAnchor.constraint(equalTo:controls.widthAnchor).isActive=true
            add(button("Set up voice later",#selector(skipVoice)))
        case .shortcut:
            heading.stringValue="Match your app’s shortcut."
            let openAI=controller.appPlugin?.id == "org.justviberemote.app.chatgpt" || app.localizedCaseInsensitiveContains("chatgpt")
            lead.stringValue=openAI ? "Open \(app)’s keyboard settings and match the dictation shortcut below." : "Find the dictation shortcut in \(app), then enter the same keys here."
            if openAI {
                add(text("Settings  ›  Keyboard Shortcuts",size:17,weight:.semibold))
                note("1. Open \(app) → Settings (⌘,).")
                note("2. Choose Keyboard Shortcuts and search “dictation”.")
                note("3. Set the dictation command to Control + Shift + M. Click the shortcut field below and press the same keys, then try them in the app’s composer.")
                note("Choose dictation for entering text. The Voice chat hotkey starts a live conversation.")
                if controller.appPlugin?.id == "org.justviberemote.app.chatgpt" { add(button("Open \(app) settings…",#selector(openAppSettings))) }
                else { add(button("Open \(app)",#selector(openApp))) }
            } else { add(button("Open \(app)",#selector(openApp))) }
            add(text("Same shortcut in both apps",size:13,weight:.semibold))
            shortcut.setAccessibilityLabel("App dictation shortcut");add(shortcut)
            shortcut.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true
            shortcut.heightAnchor.constraint(equalToConstant:36).isActive=true
            if let suggested=suggestedShortcut { note("Suggested by the \(app) plugin: \(suggested). Continue saves the keys entered above.") }
            note("Click the field, then press your shortcut, such as Control + Shift + M. Esc cancels; Tab moves to the next control.")
            add(toggle)
            note("Turn this off if you prefer to hold the remote’s button while talking.")
            if openAI { add(button("View official shortcut guide",#selector(openShortcutGuide))) }
            note("Can’t find the dictation shortcut? Choose Set up voice later.")
            add(button("Set up voice later",#selector(skipVoice)))
        case .practice:
            heading.stringValue="Try your first action.";lead.stringValue=checkpoint.wantsVoice ? "Open \(app), click an input field, and say a short phrase with your remote." : "Open \(app) and try the button you just linked."
            add(text(checkpoint.wantsVoice ? "Try saying: “My remote is ready.”":"Try: \(controller.config.bindings[selectedIndex].name) → \(controller.config.bindings[selectedIndex].action.title)",size:17,weight:.semibold))
            note(checkpoint.wantsVoice ? (controller.config.voiceMode == "toggle" ? "Press the microphone button, speak, then press it again to stop." : "Hold the microphone button while speaking, then release it.") : "Use a spare input field or draft so you can see what the button does.")
            add(button("Open \(app)",#selector(openApp)));add(button("Something didn’t work",#selector(troubleshoot)))
            add(reconnect);note("Return here when you’ve seen the expected result. Only your confirmation completes setup.")
        case .done:
            heading.stringValue="You’re ready.";lead.stringValue="\(controller.devicePlugin?.name ?? "Your remote") is set up for \(app)."
            add(text("One remote, your workflow",size:17,weight:.semibold));note("Your button links and app settings are saved for this remote.")
            note(checkpoint.wantsVoice ? "Voice setup and your first dictation test are confirmed." : "Buttons are set up. Add voice later from Voice & microphone.")
            note("Find this remote under Remotes. Open Apps to add another app profile, or Buttons to personalize more controls.")
        }
    }
    private func refresh() {
        guard !ended else { return }
        if visibleStage != checkpoint.stage { rebuildContent() }
        let stage=checkpoint.stage
        stageLabel.stringValue=stage == .done ? "ALL SET":"STEP \(stage.milestone+1) OF 5"
        for (index,row) in milestoneRows.enumerated() {
            row.update(completed:index<stage.milestone || stage == .done,current:index == stage.milestone && stage != .done)
        }
        back.isEnabled=stage != .welcome && stage != .done;back.isHidden=stage == .done;later.isHidden=stage == .done;primary.isEnabled=true
        primary.title=stage == .welcome ? "Get started":stage == .practice ? (checkpoint.wantsVoice ? "I see my text":"The button works"):stage == .done ? "Open remote":"Continue"
        feedback.textColor = .rvMuted
        illustration.contentTintColor = .rvAccent
        switch stage {
        case .permissions:
            let inputAllowed=previewPermissionCount.map { $0>=1 } ?? RemoteInput.allowed
            let shortcutsAllowed=previewPermissionCount.map { $0>=2 } ?? TargetOutput.allowed
            primary.isEnabled=inputAllowed && shortcutsAllowed
            inputPermissionRow?.setCompleted(inputAllowed);shortcutPermissionRow?.setCompleted(shortcutsAllowed)
            checkmarkArtwork.completed=(inputAllowed ? 1:0)+(shortcutsAllowed ? 1:0)
            heading.stringValue=primary.isEnabled ? "Permissions complete.":"Let your remote work with apps."
            lead.stringValue=primary.isEnabled ? "Your remote can read buttons and send your chosen actions to apps.":"macOS needs two permissions. Open each setting, switch on JustVibe Remote, then come back here."
            feedback.stringValue=primary.isEnabled ? "Everything is checked. Continue to connect your remote.":"Complete both items to continue. Return here after allowing access."
        case .receiver:
            primary.isEnabled=controller.running && controller.connected>0
            receiverConnectButton?.isHidden=primary.isEnabled
            receiverHelpButton?.isHidden=primary.isEnabled
            receiverConnectButton?.title=controller.running ? "Reconnect this remote":"Connect this remote"
            heading.stringValue=primary.isEnabled ? "Your remote is connected.":"Connect your remote."
            lead.stringValue=primary.isEnabled ? "Click Continue to set up your remote’s controls.":"Plug in the USB receiver or pair \(controller.config.profile.name) in macOS Bluetooth settings. Then connect it below."
            feedback.stringValue=primary.isEnabled ? "✓ Receiver connected. Ready to continue.":controller.status
            feedback.textColor=primary.isEnabled ? .systemGreen:.rvMuted
            illustration.contentTintColor=primary.isEnabled ? .systemGreen:.rvAccent
        case .button:
            let binding=controller.config.bindings[selectedIndex]
            learningCancel?.isHidden=controller.learningIndex == nil
            learningLink?.isEnabled=controller.learningIndex == nil
            learningLink?.title=controller.learningIndex != nil ? "Waiting for the button…":binding.usage == nil ? "Link this button":"Relink this button"
            primary.isEnabled=controller.learningIndex == nil
            feedback.stringValue=controller.learningIndex != nil ? "Press only \(binding.name) on the physical remote, or cancel learning to continue…":binding.usage == nil || binding.action == .native ? "Ready to continue with the existing controls. Customizing a button is optional.":"\(binding.name) is linked. Action: \(binding.action.title). You can continue when ready."
        case .microphone:
            if controller.learningIndex == nil { changeMicrophone() }
            let learning=controller.learningIndex != nil
            learningCancel?.isHidden = !learning
            learningLink?.isEnabled = !learning && controller.running && controller.connected>0
            let linked=controller.microphoneIndex.map { controller.config.bindings[$0].usage != nil && controller.config.bindings[$0].action == .dictate } ?? false
            let buttonComplete=linked && !learning
            primary.isEnabled=buttonComplete && micPicker.indexOfSelectedItem>0
            microphoneButtonStep?.update(completed:buttonComplete,current:!buttonComplete,status:learning ? "Waiting for your press":buttonComplete ? "Linked":"Start here")
            microphoneInputStep?.update(completed:primary.isEnabled,current:buttonComplete && !primary.isEnabled,status:primary.isEnabled ? "Selected":buttonComplete ? "Choose an input":"Up next")
            microphoneButtonHint?.stringValue=learning ? "Press and release the microphone button on your real remote now.":buttonComplete ? "Your remote’s button is ready for dictation.":"Click Set up button, then press and release the microphone button on your real remote."
            microphoneButtonHint?.textColor=buttonComplete ? .systemGreen:learning ? .rvAccent:.rvInk
            learningLink?.title=learning ? "Listening for button…":linked ? "Change button":"Set up button"
            microphoneControls?.isHidden = !buttonComplete
            microphoneLockedHint?.isHidden=buttonComplete
            let audioIndex=micPicker.indexOfSelectedItem-1
            let input=inputs.indices.contains(audioIndex) ? inputs[audioIndex]:nil
            audioTest?.isHidden=input == nil
            microphoneHelp.isHidden=input == nil
            let matches=input?.id == AudioInputs.defaultID()
            let protected=controller.config.microphones[controller.config.devicePluginID]?.guardDictation ?? true
            microphoneHelp.stringValue=input == nil ? "Choose the remote’s microphone before testing." : matches ? "The system input matches this microphone." : protected ? "The system input is different. Match it below for protected dictation, or review the safeguard in Voice & microphone." : "Choose this input in your dictation app too."
            microphoneDefaultButton?.isHidden = !protected || matches || input == nil
            feedback.stringValue = !controller.running || controller.connected == 0 ? "Reconnect your remote to set up dictation.":""
        case .practice:
            primary.isEnabled=controller.running && controller.connected>0 && RemoteInput.allowed && TargetOutput.allowed
            if !primary.isEnabled { feedback.stringValue="Reconnect this remote before testing. Use Back to review setup." }
            else if controller.voiceActive { feedback.stringValue="Voice shortcut active. Finish speaking, then check the result in your app." }
            else { feedback.stringValue=controller.status.hasPrefix("Connected ·") ? "Open your app to try it, then return here.":controller.status }
        case .app: primary.isEnabled=appPicker.selectedItem?.representedObject is String
        case .shortcut: primary.isEnabled=shortcut.shortcutValue != nil
        default: break
        }
        feedback.isHidden=feedback.stringValue.isEmpty
        let diagram=[RemoteSetupStage.button,.microphone].contains(stage)
        canvas.isHidden = !diagram;illustration.isHidden=diagram || stage == .welcome || stage == .permissions || stage == .done
        checkmarkArtwork.isHidden=stage != .permissions && stage != .done
        if stage == .done { checkmarkArtwork.completed=2 }
        remoteArtwork.isHidden=stage != .welcome;remoteArtwork.reference=controller.artwork.image;remoteArtwork.remoteLayout=controller.devicePlugin?.device?.layout
        if diagram {
            let index=stage == .microphone ? controller.microphoneIndex ?? selectedIndex:selectedIndex
            canvas.update(layout:controller.remoteLayout,bindings:controller.config.bindings,selection:stage == .welcome ? nil:controller.config.bindings[index].controlID,active:controller.activeUsages)
        } else {
            let symbol=stage == .permissions ? "hand.raised.circle":stage == .receiver ? (primary.isEnabled ? "checkmark.circle.fill":"cable.connector"):stage == .app ? "app.badge":stage == .shortcut ? "keyboard":stage == .done ? "checkmark.circle":"sparkles"
            illustration.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
        }
        if stage == .permissions { visualCaption.stringValue="\(checkmarkArtwork.completed) of 2 permissions complete";visualCaption.textColor=checkmarkArtwork.completed == 2 ? .systemGreen:.rvMuted;return }
        visualCaption.textColor = .rvMuted
        visualCaption.stringValue=stage == .done ? "Saved for this remote":stage == .button ? "Click a button to choose it":stage == .microphone ? "One button for voice":stage == .welcome ? (controller.artwork.image != nil ? "Your remote":controller.devicePlugin?.device?.layout != nil ? "Remote design":"Generic remote illustration") : "\(controller.devicePlugin?.name ?? "Your remote")"
    }
    private func move(to stage:RemoteSetupStage) {
        controller.cancelLearning();var next=checkpoint;next.stage=stage
        next.controlID=controller.config.bindings[selectedIndex].controlID
        do { try controller.saveSetupCheckpoint(next);checkpoint=next;rebuildContent();refresh() }
        catch { feedback.stringValue=error.localizedDescription }
    }
    @objc private func advance() {
        guard primary.isEnabled else { return }
        switch checkpoint.stage {
        case .done: finish()
        case .app:
            guard let id=appPicker.selectedItem?.representedObject as? String else { return }
            do {
                if id != controller.config.appPluginID {
                    try controller.selectPlugins(deviceID:controller.config.devicePluginID,appID:id)
                    checkpoint.wantsVoice=checkpoint.wantsVoice && controller.appPlugin?.app?.supports(.dictate) == true
                    shortcut.setShortcut(initialShortcut)
                }
                move(to:.permissions)
            } catch { feedback.stringValue=error.localizedDescription }
        case .shortcut:
            guard let keys=shortcut.shortcutValue else { return }
            do { var config=controller.config;config.shortcut=keys;config.shortcutConfirmed=true;config.voiceMode=toggle.state == .on ? "toggle":"hold";try controller.update(config);move(to:.practice) }
            catch { feedback.stringValue=error.localizedDescription }
        case .microphone:
            let index=micPicker.indexOfSelectedItem-1;guard inputs.indices.contains(index) else { return }
            do { var config=controller.config;let input=inputs[index];config.microphones[config.devicePluginID]=MicrophonePreference(id:input.id,name:input.name,guardDictation:config.microphones[config.devicePluginID]?.guardDictation ?? true);try controller.update(config);move(to:.shortcut) }
            catch { feedback.stringValue=error.localizedDescription }
        case .practice:
            do {
                var config=controller.config;config.autoConnect=reconnect.state == .on
                if checkpoint.wantsVoice { config.dictationTested=true }
                try controller.update(config);var done=checkpoint;done.stage = .done
                try controller.saveSetupCheckpoint(done,completed:true);checkpoint=done;rebuildContent();refresh()
            } catch { feedback.stringValue=error.localizedDescription }
        default: move(to:checkpoint.stage.next(voice:checkpoint.wantsVoice))
        }
    }
    @objc private func goBack() { move(to:checkpoint.stage.previous(voice:checkpoint.wantsVoice)) }
    @objc private func changeVoiceChoice() { checkpoint.wantsVoice=voiceChoice.state == .on;do { try controller.saveSetupCheckpoint(checkpoint) } catch { feedback.stringValue=error.localizedDescription } }
    @objc private func changeApp() {
        guard let id=appPicker.selectedItem?.representedObject as? String else { return }
        do { try controller.selectPlugins(deviceID:controller.config.devicePluginID,appID:id);checkpoint.wantsVoice=checkpoint.wantsVoice && controller.appPlugin?.app?.supports(.dictate) == true;voiceChoice.state=checkpoint.wantsVoice ? .on:.off;shortcut.setShortcut(initialShortcut);try controller.saveSetupCheckpoint(checkpoint);rebuildContent();refresh() }
        catch { feedback.stringValue=error.localizedDescription }
    }
    @objc private func chooseRemoteArtwork() {
        let picker=NSOpenPanel();picker.allowedContentTypes=[.png,.jpeg,.heic];picker.allowsMultipleSelection=false
        picker.message="Choose a clear photo or illustration of this remote."
        picker.beginSheetModal(for:panel) { [weak self] response in
            guard let self,response == .OK,let url=picker.url else { return }
            do { try self.controller.setArtwork(from:url);self.refresh() } catch { self.feedback.stringValue=error.localizedDescription }
        }
    }
    @objc private func allowInput() { if !RemoteInput.allowed { RemoteInput.requestPermission() };openPrivacy("Privacy_ListenEvent") }
    @objc private func allowShortcuts() { if !TargetOutput.allowed { TargetOutput.requestPermission() };openPrivacy("Privacy_Accessibility") }
    @objc private func connect() { do { if controller.running { try controller.stop() };controller.start();refresh() } catch { feedback.stringValue=error.localizedDescription } }
    @objc private func changeButton() { controller.cancelLearning();selectedIndex=buttonPicker.indexOfSelectedItem;checkpoint.controlID=controller.config.bindings[selectedIndex].controlID;rebuildContent();refresh() }
    @objc private func changeAction() { let index=actionPicker.indexOfSelectedItem-1;guard setupActions.indices.contains(index) else { return };do { var config=controller.config;config.bindings[selectedIndex].action=setupActions[index];try controller.update(config);refresh() } catch { feedback.stringValue=error.localizedDescription } }
    @objc private func learnButton() { controller.learn(selectedIndex);refresh() }
    @objc private func cancelLearning() { controller.cancelLearning();refresh() }
    @objc private func learnMicrophone() {
        audioTest?.select(nil)
        guard let index=controller.microphoneIndex else { feedback.stringValue="Assign Dictation to a button in the editor first, or set up voice later.";return }
        do { if controller.config.bindings[index].action != .dictate { var config=controller.config;config.bindings[index].action = .dictate;try controller.update(config) };controller.learn(index);refresh() }
        catch { feedback.stringValue=error.localizedDescription }
    }
    @objc private func skipVoice() { checkpoint.wantsVoice=false;voiceChoice.state = .off;move(to:.practice) }
    @objc private func openApp() { controller.showTargetApp() }
    @objc private func openAppSettings() { if let url=URL(string:"codex://settings") { NSWorkspace.shared.open(url) } }
    @objc private func openShortcutGuide() { if let url=URL(string:"https://learn.chatgpt.com/docs/reference/commands") { NSWorkspace.shared.open(url) } }
    @objc private func troubleshoot() { move(to:checkpoint.wantsVoice ? .microphone:.button) }
    @objc private func checkConnection() { guard connectionCheck == nil else { return };let check=ConnectionCheck(controller:controller,parent:panel);connectionCheck=check;check.finished={ [weak self] in self?.connectionCheck=nil;self?.refresh() };check.show() }
    @objc private func changeMicrophone() {
        let index=micPicker.indexOfSelectedItem-1
        audioTest?.select(inputs.indices.contains(index) ? inputs[index]:nil)
    }
    @objc private func useSelectedMicrophone() {
        let index=micPicker.indexOfSelectedItem-1;guard inputs.indices.contains(index) else { return }
        do { try AudioInputs.makeDefault(inputs[index]);refresh() } catch { feedback.stringValue=error.localizedDescription }
    }
    private func openPrivacy(_ anchor:String) { if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) } }
    @objc private func cancel() { do { try controller.saveSetupCheckpoint(checkpoint) } catch { feedback.stringValue=error.localizedDescription;return };finish() }
    private func finish() {
        guard !ended else { return };ended=true;audioTest?.close();timer?.invalidate();timer=nil;controller.cancelLearning();controller.stopVoice()
        if !controller.config.remoteSetupCompleted && !wasRunning { try? controller.stop() }
        parent?.endSheet(panel);panel.orderOut(nil);finished?()
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { cancel();return false }
    func render(to url:URL,stage:RemoteSetupStage? = nil,permissionCount:Int? = nil) throws {
        previewPermissionCount=permissionCount.map { min(2,max(0,$0)) }
        if let stage { checkpoint.stage=stage;rebuildContent();refresh() }
        guard let view=panel.contentView else { return };view.layoutSubtreeIfNeeded()
        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds),let png:Data = { () -> Data? in view.cacheDisplay(in:view.bounds,to:bitmap);return bitmap.representation(using:.png,properties:[:]) }() { try png.write(to:url) }
    }
}

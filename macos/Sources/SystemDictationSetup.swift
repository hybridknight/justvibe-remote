import AppKit

private final class DictationSetupDocument:NSView { override var isFlipped:Bool { true } }

/// A real sheet keeps shortcut focus and form layout stable, including errors.
/// Constructing or showing it never changes settings or starts dictation.
final class SystemDictationSetup:NSObject,NSWindowDelegate {
    private let controller:RemoteController
    private weak var parent:NSWindow?
    let panel:NSPanel
    let mode=NSPopUpButton(),buttonPicker=NSPopUpButton(),presetPicker=NSPopUpButton()
    let recorder=ShortcutRecorder(frame:.zero)
    let confirmation=NSButton(checkboxWithTitle:"Dictation is on and this option matches macOS Keyboard settings",target:nil,action:nil)
    private let error=NSTextField(wrappingLabelWithString:"")
    private let explanation=NSTextField(wrappingLabelWithString:"")
    private let customRow=NSStackView(),stack=NSStackView()
    private let scroll=NSScrollView(),document=DictationSetupDocument()
    private let controls:[Binding]
    private var ended=false
    var finished:(()->Void)?
    init(controller:RemoteController,parent:NSWindow) {
        self.controller=controller;self.parent=parent
        controls=controller.config.bindings.filter { $0.controlID != nil }
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:640,height:min(540,((parent.screen ?? NSScreen.main)?.visibleFrame.height ?? 900)-80)),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init()
        panel.title="Dictation in any app";panel.delegate=self;panel.isReleasedWhenClosed=false
        panel.appearance=NSAppearance(named:.aqua)
        build()
        let saved=controller.systemDictationSettings
        let initialMode=controller.config.systemDictation[controller.config.devicePluginID] == nil ? SystemDictationMode.fallback:saved.mode
        mode.selectItem(at:SystemDictationMode.allCases.firstIndex(of:initialMode) ?? 0)
        buttonPicker.selectItem(at:controls.firstIndex(where:{$0.controlID == saved.controlID}) ?? 0)
        let initialPreset=saved.preset ?? (saved.shortcut.isEmpty ? .controlTwice:.custom)
        presetPicker.selectItem(at:SystemDictationShortcut.allCases.firstIndex(of:initialPreset) ?? 0)
        recorder.setShortcut(saved.shortcut);confirmation.state=saved.confirmed ? .on:.off
        recorder.changed={ [weak self] in self?.confirmation.state = .off;self?.error.stringValue="";self?.fitDocument() }
        updatePreset()
        scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func text(_ value:String,size:CGFloat=13,bold:Bool=false)->NSTextField {
        let field=NSTextField(wrappingLabelWithString:value)
        field.font = WorkspaceTypography.text(size,weight:bold ? .semibold:.regular);field.textColor = .labelColor
        return field
    }
    private func add(_ view:NSView) {
        stack.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
    }
    private func build() {
        let root=WorkspaceSurface(.card);panel.contentView=root
        scroll.frame=NSRect(x:0,y:64,width:640,height:panel.contentView!.bounds.height-64)
        scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        root.addSubview(scroll);scroll.documentView=document
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=WorkspaceSpacing.controls;stack.detachesHiddenViews=true
        document.translatesAutoresizingMaskIntoConstraints=false
        stack.translatesAutoresizingMaskIntoConstraints=false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:WorkspaceSpacing.inset),
            stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-WorkspaceSpacing.inset),
            stack.topAnchor.constraint(equalTo:document.topAnchor,constant:WorkspaceSpacing.inset),
            stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-WorkspaceSpacing.inset),
        ])
        add(text("Dictation in any app",size:23,bold:true))
        add(text("Choose the same shortcut option shown in macOS System Settings → Keyboard → Dictation. No need to record double-press shortcuts."))
        add(text("Use macOS Dictation",bold:true))
        mode.addItems(withTitles:SystemDictationMode.allCases.map(\.title));mode.setAccessibilityLabel("Where to use macOS Dictation");add(mode)
        add(text("Remote button",bold:true))
        buttonPicker.addItems(withTitles:controls.map(\.name));buttonPicker.setAccessibilityLabel("Button for dictation in any app");add(buttonPicker)
        add(text("macOS Dictation shortcut",bold:true))
        presetPicker.addItems(withTitles:SystemDictationShortcut.allCases.map(\.title))
        presetPicker.setAccessibilityLabel("macOS Dictation shortcut option");presetPicker.target=self;presetPicker.action=#selector(changePreset);add(presetPicker)
        customRow.orientation = .vertical;customRow.alignment = .leading;customRow.spacing=WorkspaceSpacing.related
        let customHelp=text("Click the field, then press a modifier plus a key, or F1–F20. Escape cancels recording.",size:12)
        customRow.addArrangedSubview(customHelp);customHelp.widthAnchor.constraint(equalTo:customRow.widthAnchor).isActive=true
        customRow.addArrangedSubview(recorder);recorder.widthAnchor.constraint(equalTo:customRow.widthAnchor).isActive=true
        recorder.heightAnchor.constraint(equalToConstant:38).isActive=true;recorder.setAccessibilityLabel("Record custom macOS Dictation shortcut")
        add(customRow)
        explanation.font = WorkspaceTypography.body(12);explanation.textColor = .secondaryLabelColor;add(explanation)
        confirmation.target=self;confirmation.action=#selector(clearError);add(confirmation)
        add(text("Press the remote button once to start, then again to stop. Fallback mode keeps configured native app dictation first.",size:12))
        let settings=NSButton(title:"Open macOS Keyboard settings…",target:self,action:#selector(openKeyboardSettings));settings.bezelStyle = .rounded;add(settings)
        error.textColor = .systemRed;error.font = WorkspaceTypography.body(12);add(error)
        let cancel=NSButton(title:"Cancel",target:self,action:#selector(close));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}"
        let save=NSButton(title:"Save",target:self,action:#selector(save));save.bezelStyle = .rounded;save.keyEquivalent="\r"
        root.addSubview(cancel);root.addSubview(save)
        cancel.translatesAutoresizingMaskIntoConstraints=false;save.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            save.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-WorkspaceSpacing.inset),save.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16),
            save.widthAnchor.constraint(equalToConstant:100),save.heightAnchor.constraint(equalToConstant:32),
            cancel.trailingAnchor.constraint(equalTo:save.leadingAnchor,constant:-12),cancel.centerYAnchor.constraint(equalTo:save.centerYAnchor),
            cancel.widthAnchor.constraint(equalToConstant:100),cancel.heightAnchor.constraint(equalToConstant:32),
        ])
        WorkspaceTypography.apply(to:root)
        panel.defaultButtonCell=save.cell as? NSButtonCell
        panel.initialFirstResponder=presetPicker
    }
    var selectedPreset:SystemDictationShortcut { SystemDictationShortcut.allCases[max(0,presetPicker.indexOfSelectedItem)] }
    @objc private func changePreset() { confirmation.state = .off;error.stringValue="";recorder.window?.makeFirstResponder(presetPicker);updatePreset() }
    private func updatePreset() {
        customRow.isHidden=selectedPreset != .custom
        explanation.stringValue=selectedPreset == .microphone
            ? "Uses macOS’s Fn+D Dictation command, the software equivalent of the microphone key."
            : selectedPreset == .custom ? "Match your customized shortcut in macOS Keyboard settings."
            : "Select “\(selectedPreset.title)” in macOS Keyboard settings too. JustVibe sends the two presses for you."
        fitDocument()
    }
    private func fitDocument() {
        panel.contentView?.layoutSubtreeIfNeeded()
    }
    @objc private func clearError() { error.stringValue="";fitDocument() }
    @objc private func openKeyboardSettings() {
        if let url=URL(string:"x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    @objc func save() {
        do {
            var setting=SystemDictationSettings()
            setting.mode=SystemDictationMode.allCases[max(0,mode.indexOfSelectedItem)]
            setting.preset=selectedPreset;setting.shortcut=recorder.shortcutValue ?? ""
            setting.confirmed=confirmation.state == .on
            if controls.indices.contains(buttonPicker.indexOfSelectedItem) { setting.controlID=controls[buttonPicker.indexOfSelectedItem].controlID! }
            try controller.saveSystemDictation(setting);close()
        } catch { self.error.stringValue=error.localizedDescription;fitDocument();document.scrollToVisible(self.error.convert(self.error.bounds,to:document)) }
    }
    func show() { fitDocument();parent?.beginSheet(panel) }
    @objc func close() {
        guard !ended else { return };ended=true
        parent?.endSheet(panel);panel.orderOut(nil);finished?()
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { close();return false }
}

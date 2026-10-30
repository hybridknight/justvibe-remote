import AppKit
import AVFoundation

/// A bounded, in-memory preview. Merely displaying this view never opens an input.
final class SetupMicrophoneTest: NSStackView {
    private let controller: RemoteController
    private let audio = MicrophoneCapture()
    private var input: AudioInput?
    private var token = UUID(), waiting = false, suspended = false, active = true
    private var started = Date(), scanned = Date.distantPast
    private var timer: Timer?
    private let meter = NSLevelIndicator()
    private let result = NSTextField(wrappingLabelWithString: "Choose a microphone, then start a short test.")
    private var startButton: NSButton!, stopButton: NSButton!, playButton: NSButton!, clearButton: NSButton!

    init(controller: RemoteController,showTitle:Bool = true) {
        self.controller = controller
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = WorkspaceSpacing.controls
        let title = NSTextField(labelWithString: "Test your microphone here")
        title.font = WorkspaceTypography.heading(15, weight: .semibold); if showTitle { addArrangedSubview(title) }
        meter.minValue = 0; meter.maxValue = 100; meter.levelIndicatorStyle = .continuousCapacity
        meter.setAccessibilityLabel("Microphone input level")
        addArrangedSubview(meter); meter.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        result.font = WorkspaceTypography.body(12); result.textColor = .rvMuted
        addArrangedSubview(result); result.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        startButton = PrimaryButton(title: "Record 5 seconds", target: self, action: #selector(startTest));startButton.isBordered=false
        startButton.widthAnchor.constraint(equalToConstant:160).isActive=true;startButton.heightAnchor.constraint(equalToConstant:36).isActive=true
        stopButton = NSButton(title: "Stop", target: self, action: #selector(stopTest))
        playButton = NSButton(title: "Play back", target: self, action: #selector(playClip))
        clearButton = NSButton(title: "Clear", target: self, action: #selector(clearClip))
        let controls = NSStackView(views: [startButton, stopButton, playButton, clearButton]); controls.spacing = WorkspaceSpacing.related
        addArrangedSubview(controls)
        let help = NSTextField(wrappingLabelWithString: "Speak near the remote while recording. Hold its microphone button if needed. Your clip stays on this computer and is cleared when you leave.")
        help.font = WorkspaceTypography.body(12); help.textColor = .rvMuted; addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        WorkspaceTypography.apply(to:self)
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func select(_ input: AudioInput?) {
        guard self.input?.id != input?.id else { return }
        reset(); self.input = input
        result.stringValue = input.map { "Ready to record from \($0.name)." } ?? "Choose a microphone before recording."
        result.textColor = .rvMuted
        updateButtons()
    }
    private func updateButtons() {
        startButton.isEnabled = active && input != nil && !audio.recording && !waiting
        stopButton.isEnabled = audio.recording || waiting
        playButton.isEnabled = audio.hasClip && !audio.recording && !waiting
        clearButton.isEnabled = audio.hasClip && !audio.recording && !waiting
        stopButton.isHidden = !audio.recording && !waiting
        playButton.isHidden = !audio.hasClip || audio.recording || waiting
        clearButton.isHidden = !audio.hasClip || audio.recording || waiting
    }
    @objc private func startTest() {
        guard active, !waiting, !audio.recording, let input else { return }
        reset(); controller.beginMicrophoneTest(); suspended = true
        let request = UUID(); token = request; waiting = true; updateButtons()
        result.stringValue = "Waiting for microphone access…"
        result.textColor = .rvMuted
        let begin: (Bool) -> Void = { [weak self] granted in
            guard let self, self.active, self.token == request, self.input?.id == input.id else { return }
            self.waiting = false
            guard granted else {
                self.result.stringValue = "Allow JustVibe Remote in System Settings → Privacy & Security → Microphone, then retry."
                self.releaseRemote(); self.updateButtons(); return
            }
            do {
                try self.audio.start(input); self.started = Date()
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
                self.timer = timer; RunLoop.main.add(timer, forMode: .common); self.refresh()
            } catch { self.result.stringValue = error.localizedDescription; self.releaseRemote() }
            self.updateButtons()
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in DispatchQueue.main.async { begin(granted) } }
        } else { begin(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) }
    }
    private func refresh() {
        if Date().timeIntervalSince(scanned) >= 1 {
            scanned = Date()
            if !AudioInputs.list().contains(where: { $0.id == audio.inputID }) {
                stopTest(); result.stringValue = "Microphone disconnected. Reconnect it and retry; no other input was used."; return
            }
        }
        if let error = audio.error { stopTest(); result.stringValue = error; return }
        meter.doubleValue = audio.meterPercent
        let elapsed = Date().timeIntervalSince(started)
        result.stringValue = "Recording · \(max(1, Int(ceil(5 - elapsed)))) seconds left · Speak into \(input?.name ?? "your remote")."
        if audio.full || elapsed >= 5 { stopTest() }
    }
    @objc private func stopTest() {
        token = UUID(); waiting = false; timer?.invalidate(); timer = nil; audio.stop(); meter.doubleValue = 0
        result.stringValue = audio.sampleCount == 0 ? "No audio received. Hold the remote’s mic button while speaking, then retry." : !audio.hasSignal ? "Audio arrived, but it was silent. Check the mic button and input volume, then retry." : "✓ Audio received. Play back to check that you can hear your voice."
        result.textColor=audio.hasSignal ? .systemGreen:.rvMuted
        // Keep mapped actions paused through playback; release when leaving or clearing.
        if !audio.hasClip { releaseRemote() }
        updateButtons()
    }
    @objc private func playClip() { do { try audio.play() } catch { result.stringValue = error.localizedDescription } }
    @objc private func clearClip() { reset(); result.stringValue = "Clip cleared. Ready for another test."; updateButtons() }
    private func releaseRemote() { if suspended { suspended = false; controller.endMicrophoneTest() } }
    private func reset() {
        token = UUID(); waiting = false; timer?.invalidate(); timer = nil
        audio.clear(); meter.doubleValue = 0; releaseRemote()
    }
    func close() { active = false; reset(); updateButtons() }
    deinit { timer?.invalidate(); audio.clear() }
}

/// The everyday test surface. Selection is saved per remote; audio is opened
/// only by the explicit Start button in SetupMicrophoneTest.
final class VoiceMicrophonePanel:NSStackView {
    private let controller:RemoteController
    private let picker=NSPopUpButton()
    private let status=NSTextField(wrappingLabelWithString:"")
    private let test:SetupMicrophoneTest
    private var inputs:[AudioInput]=[]
    private var closed=false
    init(controller:RemoteController) {
        self.controller=controller;test=SetupMicrophoneTest(controller:controller,showTitle:false)
        super.init(frame:.zero)
        orientation = .vertical;alignment = .leading;spacing=WorkspaceSpacing.section
        let inputLabel=NSTextField(labelWithString:"AUDIO INPUT");inputLabel.font = WorkspaceTypography.body(10,weight:.semibold);inputLabel.textColor = .rvMuted;addArrangedSubview(inputLabel)
        picker.target=self;picker.action=#selector(selectInput);picker.setAccessibilityLabel("Microphone for this remote")
        let refresh=NSButton(title:"Refresh inputs",target:self,action:#selector(reload))
        let row=NSStackView(views:[picker,refresh]);row.spacing=WorkspaceSpacing.related;addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo:widthAnchor).isActive=true
        picker.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        status.font = WorkspaceTypography.body(12);status.textColor = .rvMuted
        addArrangedSubview(status)
        let levelLabel=NSTextField(labelWithString:"INPUT LEVEL");levelLabel.font = WorkspaceTypography.body(10,weight:.semibold);levelLabel.textColor = .rvMuted;addArrangedSubview(levelLabel)
        addArrangedSubview(test)
        test.widthAnchor.constraint(equalTo:widthAnchor).isActive=true
        status.widthAnchor.constraint(equalTo:widthAnchor).isActive=true
        WorkspaceTypography.apply(to:self)
        reload()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    private var selected:AudioInput? {
        let index=picker.indexOfSelectedItem-1
        return inputs.indices.contains(index) ? inputs[index]:nil
    }
    @objc private func reload() {
        guard !closed else { return }
        let id=selected?.id ?? controller.config.microphones[controller.config.devicePluginID]?.id
        test.select(nil);inputs=AudioInputs.list();picker.removeAllItems();picker.addItem(withTitle:"Choose the remote’s microphone…")
        for input in inputs { picker.addItem(withTitle:input.name + (input.usb ? " · USB":"")) }
        if let index=inputs.firstIndex(where:{$0.id == id}) { picker.selectItem(at:index+1) }
        status.stringValue=selected != nil ? "Selected for this remote.":id != nil ? "The saved microphone is unavailable. Reconnect it and refresh, or choose another input.":"Choose the microphone you want to hear."
        test.select(selected)
    }
    @objc private func selectInput() {
        guard !closed else { return };test.select(nil)
        guard let input=selected else { status.stringValue="Choose a microphone to test.";return }
        do {
            var config=controller.config
            let protect=config.microphones[config.devicePluginID]?.guardDictation ?? true
            config.microphones[config.devicePluginID]=MicrophonePreference(id:input.id,name:input.name,guardDictation:protect)
            try controller.update(config)
            test.select(input);status.stringValue="Selected for this remote."
        } catch { reload();status.stringValue=error.localizedDescription }
    }
    func close() { guard !closed else { return };closed=true;test.close() }
    deinit { test.close() }
}

import AppKit
import AVFoundation

final class MicrophoneTest: NSObject, NSWindowDelegate {
    private let controller: RemoteController
    private weak var parent: NSWindow?
    private let panel: NSPanel
    private let picker = NSPopUpButton()
    private let source = NSTextField(wrappingLabelWithString: "")
    private let system = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextField(wrappingLabelWithString: "Choose your remote’s microphone, then start a short test.")
    private let meter = NSLevelIndicator()
    private let protect = NSButton(checkboxWithTitle: "Block remote dictation when system input differs", target: nil, action: nil)
    private var record: NSButton!, play: NSButton!
    private var inputs: [AudioInput] = []
    private let audio = MicrophoneCapture()
    private var timer: Timer?, started = Date(), lastScan = Date.distantPast
    private var ended = false, requestingPermission = false, requestToken = UUID()
    var finished: (() -> Void)?
    init(controller: RemoteController, parent: NSWindow) {
        self.controller = controller; self.parent = parent
        panel = NSPanel(contentRect: NSRect(x:0,y:0,width:650,height:780),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(); panel.title = "Microphone test"; panel.delegate = self; panel.isReleasedWhenClosed = false; panel.appearance = NSAppearance(named:.aqua)
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.white.cgColor; panel.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:26)])
        func label(_ text: String, _ size: CGFloat = 12) -> NSTextField { let label = NSTextField(wrappingLabelWithString:text); label.font = .systemFont(ofSize:size); label.textColor = .rvInk; return label }
        let heading = label("Hear your remote’s microphone",24); heading.font = .systemFont(ofSize:24,weight:.bold); stack.addArrangedSubview(heading)
        stack.addArrangedSubview(label("Choose the remote’s USB audio input. A USB label identifies its connection type; it does not prove which remote it belongs to."))
        picker.target = self; picker.action = #selector(selectInput); picker.widthAnchor.constraint(equalToConstant:580).isActive = true
        let refresh = NSButton(title:"Refresh",target:self,action:#selector(reload))
        stack.addArrangedSubview(picker); stack.addArrangedSubview(NSStackView(views:[refresh,NSButton(title:"Microphone permissions…",target:self,action:#selector(permissions))]))
        source.font = .systemFont(ofSize:12,weight:.semibold); stack.addArrangedSubview(source)
        meter.minValue = 0; meter.maxValue = 100; meter.levelIndicatorStyle = .continuousCapacity; meter.widthAnchor.constraint(equalToConstant:580).isActive = true; stack.addArrangedSubview(meter)
        result.font = .systemFont(ofSize:12); result.textColor = .rvMuted; stack.addArrangedSubview(result)
        record = NSButton(title:"Start 5-second test",target:self,action:#selector(startTest)); play = NSButton(title:"Play back",target:self,action:#selector(playClip))
        stack.addArrangedSubview(NSStackView(views:[record,NSButton(title:"Stop",target:self,action:#selector(stopTest)),play,NSButton(title:"Delete clip",target:self,action:#selector(deleteClip))]))
        stack.addArrangedSubview(label("Hold the remote’s mic button while speaking if needed. Try speaking close to the remote, away from the computer. Preview uses channel 1 and stays in memory; it is deleted on close."))
        system.font = .systemFont(ofSize:12); stack.addArrangedSubview(system)
        stack.addArrangedSubview(NSButton(title:"Use selected mic as system input",target:self,action:#selector(makeDefault)))
        protect.state = controller.config.microphones[controller.config.devicePluginID]?.guardDictation == false ? .off : .on; stack.addArrangedSubview(protect)
        stack.addArrangedSubview(label("ChatGPT input is not verified here. In your app, choose this same microphone or System Default. Close this test, then dictate a phrase in the app. The meter alone does not verify ChatGPT’s audio source."))
        stack.addArrangedSubview(NSStackView(views:[NSButton(title:"Save microphone choice",target:self,action:#selector(save)),NSButton(title:"Close",target:self,action:#selector(close))]))
        reload()
    }
    private var selected: AudioInput? { let i = picker.indexOfSelectedItem - 1; return inputs.indices.contains(i) ? inputs[i] : nil }
    func show() {
        controller.beginMicrophoneTest(); parent?.beginSheet(panel)
        let update=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in self?.refresh() }
        timer=update;RunLoop.main.add(update,forMode:.common)
    }
    @objc private func reload() {
        requestToken = UUID()
        let id = selected?.id ?? controller.config.microphones[controller.config.devicePluginID]?.id
        audio.clear(); inputs = AudioInputs.list(); picker.removeAllItems(); picker.addItem(withTitle:"Select microphone…")
        for input in inputs { picker.addItem(withTitle:input.name + (input.usb ? " · USB" : "") + (input.id == AudioInputs.defaultID() ? " · system input" : "")) }
        if let i = inputs.firstIndex(where: { $0.id == id }) { picker.selectItem(at:i + 1) }
        else if id == nil {
            let suggestions = inputs.indices.filter { inputs[$0].usb && inputs[$0].id.localizedCaseInsensitiveContains(controller.config.profile.name) }
            if suggestions.count == 1 { picker.selectItem(at:suggestions[0] + 1); result.stringValue = "Suggested from the receiver’s name. Speak into the remote and play it back to confirm; then save your choice." }
        }
        updateLabels()
    }
    @objc private func selectInput() { requestToken = UUID(); audio.clear(); result.stringValue = "Ready. This test opens only the selected microphone."; updateLabels() }
    private func updateLabels() {
        source.stringValue = selected.map { "Test input: \($0.name)" } ?? "No microphone selected. No input fallback is used."
        let current = AudioInputs.defaultID(); let name = inputs.first(where: { $0.id == current })?.name ?? "Unavailable"
        system.stringValue = "System input: \(name)\n" + (selected?.id == current && !current.isEmpty ? "Matches selected mic. Your app can still override this." : "Does not match the selected mic. Change it before protected dictation.")
        record.isEnabled = selected != nil && !audio.recording && !requestingPermission; play.isEnabled = audio.hasClip && !audio.recording
    }
    private func refresh() {
        if Date().timeIntervalSince(lastScan) > 1 {
            lastScan = Date()
            if audio.recording && !AudioInputs.list().contains(where: { $0.id == audio.inputID }) { audio.stop(); result.stringValue = "Microphone disconnected. Test stopped; no other input was used." }
            updateLabels()
        }
        if let error = audio.error { audio.stop(); result.stringValue = error; updateLabels(); return }
        meter.doubleValue = audio.meterPercent
        if audio.recording {
            let signal=audio.decibels.map { String(format:"%.0f dB",$0) } ?? "silent"
            result.stringValue = "Testing \(selected?.name ?? "selected input") · \(max(0,5 - Int(Date().timeIntervalSince(started)))) seconds left · \(audio.bufferCount) buffers / \(audio.sampleCount) samples · \(signal)"
            if audio.full || Date().timeIntervalSince(started) >= 5 { stopTest() }
        }
    }
    @objc private func startTest() {
        guard let input = selected else { return }
        audio.clear(); result.stringValue="Starting the selected microphone…"; let token = UUID(); requestToken = token
        func begin() {
            guard !self.ended, self.requestToken == token, self.selected?.id == input.id else { return }
            self.requestingPermission=false
            do { try self.audio.start(input); self.started = Date(); self.updateLabels() } catch { self.result.stringValue = error.localizedDescription;self.updateLabels() }
        }
        if AVCaptureDevice.authorizationStatus(for:.audio) == .notDetermined {
            requestingPermission=true;result.stringValue="Waiting for macOS microphone approval…";updateLabels()
            AVCaptureDevice.requestAccess(for:.audio) { granted in DispatchQueue.main.async { if granted { begin() } else { self.requestingPermission=false;self.result.stringValue = "Microphone access denied. Enable JustVibe Remote in System Settings → Privacy & Security → Microphone.";self.updateLabels() } } }
        } else { begin() }
    }
    @objc private func stopTest() {
        requestToken=UUID();requestingPermission=false;audio.stop()
        if audio.sampleCount == 0 { result.stringValue="No audio frames arrived from this mic. Hold the remote mic button and retry; reconnect the receiver if it stays at zero buffers." }
        else if !audio.hasSignal { result.stringValue="Received \(audio.sampleCount) samples, but they are completely silent. The device is open; check its mic button, batteries, and macOS input volume." }
        else { result.stringValue="Received \(audio.sampleCount) samples from this input. Play back the local clip to confirm you hear your voice." }
        updateLabels()
    }
    @objc private func playClip() { do { try audio.play() } catch { result.stringValue = error.localizedDescription }; updateLabels() }
    @objc private func deleteClip() { requestToken = UUID(); requestingPermission=false;audio.clear(); meter.doubleValue = 0; result.stringValue = "Preview deleted."; updateLabels() }
    @objc private func permissions() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
    @objc private func makeDefault() { guard let input = selected else { return }; do { try AudioInputs.makeDefault(input); updateLabels() } catch { result.stringValue = error.localizedDescription } }
    @objc private func save() {
        guard let input = selected else { result.stringValue = "Choose a microphone first."; return }
        do { var config = controller.config; config.microphones[config.devicePluginID] = MicrophonePreference(id:input.id,name:input.name,guardDictation:protect.state == .on); try controller.update(config); result.stringValue = "Saved for this remote. Close the test and try dictation in your app." }
        catch { result.stringValue = error.localizedDescription }
    }
    @objc private func close() { guard !ended else { return }; ended = true; requestToken = UUID(); timer?.invalidate(); timer = nil; audio.clear(); controller.endMicrophoneTest(); parent?.endSheet(panel); panel.orderOut(nil); finished?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { close(); return false }
    func render(to url: URL) throws { guard let view = panel.contentView else { return }; view.layoutSubtreeIfNeeded(); if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap); if let png = bitmap.representation(using:.png,properties:[:]) { try png.write(to:url) } } }
}

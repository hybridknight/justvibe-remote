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

    init(controller: RemoteController) {
        self.controller = controller
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 10
        let title = NSTextField(labelWithString: "Test your microphone here")
        title.font = .systemFont(ofSize: 15, weight: .semibold); addArrangedSubview(title)
        meter.minValue = 0; meter.maxValue = 100; meter.levelIndicatorStyle = .continuousCapacity
        meter.setAccessibilityLabel("Microphone input level")
        addArrangedSubview(meter); meter.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        result.font = .systemFont(ofSize: 12); result.textColor = .rvMuted
        addArrangedSubview(result); result.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        startButton = NSButton(title: "Start 5-second test", target: self, action: #selector(startTest))
        stopButton = NSButton(title: "Stop", target: self, action: #selector(stopTest))
        playButton = NSButton(title: "Play back", target: self, action: #selector(playClip))
        clearButton = NSButton(title: "Clear", target: self, action: #selector(clearClip))
        let controls = NSStackView(views: [startButton, stopButton, playButton, clearButton]); controls.spacing = 8
        addArrangedSubview(controls)
        let help = NSTextField(wrappingLabelWithString: "Press Start, then speak near the remote. Hold its mic button if needed. Play back to check your voice. The clip stays in memory and is deleted when you leave this step.")
        help.font = .systemFont(ofSize: 12); help.textColor = .rvMuted; addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        updateButtons()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func select(_ input: AudioInput?) {
        guard self.input?.id != input?.id else { return }
        reset(); self.input = input
        result.stringValue = input.map { "Ready to test \($0.name). Recording starts only when you press Start." } ?? "Choose a microphone before testing."
        updateButtons()
    }
    private func updateButtons() {
        startButton.isEnabled = active && input != nil && !audio.recording && !waiting
        stopButton.isEnabled = audio.recording || waiting
        playButton.isEnabled = audio.hasClip && !audio.recording && !waiting
        clearButton.isEnabled = audio.hasClip && !audio.recording && !waiting
    }
    @objc private func startTest() {
        guard active, !waiting, !audio.recording, let input else { return }
        reset(); controller.beginMicrophoneTest(); suspended = true
        let request = UUID(); token = request; waiting = true; updateButtons()
        result.stringValue = "Waiting for microphone access…"
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

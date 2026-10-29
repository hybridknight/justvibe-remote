import AppKit

/// Encoding uses the same physical keys and grammar as shortcut output.
enum ShortcutCapture {
    static func encode(keyCode:UInt16,modifiers:NSEvent.ModifierFlags)->String? {
        guard !modifiers.contains(.function),
              let key=MacShortcut.keyCodes.first(where:{$0.value == keyCode && $0.key != "ENTER"})?.key else { return nil }
        var parts:[String]=[]
        if modifiers.contains(.control) { parts.append("CTRL") }
        if modifiers.contains(.option) { parts.append("OPTION") }
        if modifiers.contains(.shift) { parts.append("SHIFT") }
        if modifiers.contains(.command) { parts.append("CMD") }
        parts.append(key)
        return parts.joined(separator:"+")
    }
    static func display(_ value:String)->String {
        value.split(separator:"+").map { token in
            ["CTRL":"⌃","OPTION":"⌥","SHIFT":"⇧","CMD":"⌘","SPACE":"Space","RETURN":"↩","ESC":"⎋","BACKSPACE":"⌫"][String(token)] ?? String(token)
        }.joined(separator:" ")
    }
}

/// Captures only while this control has focus; no global keyboard listener.
final class ShortcutRecorder:NSControl {
    private(set) var shortcutValue:String?
    var changed:(()->Void)?
    private var monitor:Any?
    private var pendingKeyRelease:UInt16?
    private var recording=false
    private var message=""
    override var acceptsFirstResponder:Bool { isEnabled }
    override var intrinsicContentSize:NSSize { NSSize(width:300,height:32) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        isEnabled=true;focusRingType = .exterior
        setAccessibilityElement(true);setAccessibilityRole(.button)
        setAccessibilityLabel("Record dictation shortcut")
        setAccessibilityHelp("Click, then press the shortcut keys. Escape cancels recording. Tab moves to the next control.")
        updateAccessibility()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    /// Load a saved or suggested chord without treating it as a new key press.
    func setShortcut(_ value:String?) {
        recording=false;message="";stopListening()
        shortcutValue=value.flatMap { $0.isEmpty ? nil:$0 }
        updateAccessibility();needsDisplay=true
    }
    @objc func optionChanged(_ sender:Any?) { changed?() }
    private func listenWhileFocused() {
        guard monitor == nil else { return }
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp]) { [weak self] event in
            guard let self,self.window?.isKeyWindow == true,
                  self.window?.firstResponder === self,event.window === self.window else { return event }
            if event.keyCode == self.pendingKeyRelease {
                if event.type == .keyUp { self.stopListening() }
                return nil
            }
            guard self.recording,event.type == .keyDown else { return event }
            self.consume(event);return nil
        }
    }
    private func stopListening() { pendingKeyRelease=nil;if let monitor { NSEvent.removeMonitor(monitor);self.monitor=nil } }
    override func mouseDown(with event:NSEvent) { beginRecording() }
    override func accessibilityPerformPress()->Bool { beginRecording();return true }
    private func beginRecording() {
        guard isEnabled else { return }
        window?.makeFirstResponder(self);recording=true;message="";listenWhileFocused();updateAccessibility();needsDisplay=true
    }
    override func becomeFirstResponder()->Bool {
        recording=true;message="";listenWhileFocused();updateAccessibility();needsDisplay=true;return true
    }
    override func resignFirstResponder()->Bool {
        recording=false;message="";stopListening();updateAccessibility();needsDisplay=true;return true
    }
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        guard recording,window?.firstResponder === self,window?.isKeyWindow == true else { return false }
        consume(event);return true
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 48 {
            recording=false;stopListening()
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        guard recording else { super.keyDown(with:event);return }
        consume(event)
    }
    private func consume(_ event:NSEvent) {
        if event.keyCode == 48 {
            recording=false;stopListening()
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        let modifiers=event.modifierFlags.intersection([.control,.option,.shift,.command])
        if event.keyCode == 53 && modifiers.isEmpty {
            recording=false;message="";stopListening();updateAccessibility();needsDisplay=true;return
        }
        guard let value=ShortcutCapture.encode(keyCode:event.keyCode,modifiers:event.modifierFlags) else {
            message="Unsupported key. Try another shortcut.";needsDisplay=true;return
        }
        shortcutValue=value;recording=false;message="";pendingKeyRelease=event.keyCode;updateAccessibility();needsDisplay=true
        changed?()
        sendAction(action,to:target)
    }
    private func updateAccessibility() {
        setAccessibilityValue(recording ? "Recording. Press shortcut keys.":shortcutValue.map(ShortcutCapture.display) ?? "No shortcut recorded")
    }
    override func draw(_ dirtyRect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7)
        NSColor.controlBackgroundColor.setFill();shape.fill()
        (recording ? NSColor.rvAccent:NSColor.separatorColor).setStroke();shape.lineWidth=recording ? 2:1;shape.stroke()
        let title = !message.isEmpty ? message:recording ? "Press shortcut keys…":shortcutValue.map(ShortcutCapture.display) ?? "Click to record shortcut"
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13,weight:shortcutValue != nil && !recording ? .semibold:.regular),.foregroundColor:recording ? NSColor.rvAccent:NSColor.labelColor]
        let text=title as NSString
        text.draw(at:NSPoint(x:12,y:bounds.midY-text.size(withAttributes:attributes).height/2),withAttributes:attributes)
        if shortcutValue != nil && !recording && message.isEmpty {
            let hint="Click to record" as NSString
            let style:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor]
            let size=hint.size(withAttributes:style)
            if text.size(withAttributes:attributes).width+size.width+40<bounds.width {
                hint.draw(at:NSPoint(x:bounds.maxX-size.width-12,y:bounds.midY-size.height/2),withAttributes:style)
            }
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds,xRadius:7,yRadius:7).fill() }
    override var focusRingMaskBounds:NSRect { bounds }
}

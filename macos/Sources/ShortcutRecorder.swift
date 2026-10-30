import AppKit
import Carbon

/// Own only our temporary requests; never undo another control's input protection.
final class ShortcutInputPriority {
    private let enable:()->OSStatus
    private let disable:()->OSStatus
    private let push:()->UnsafeMutableRawPointer?
    private let pop:(UnsafeMutableRawPointer)->Void
    private var token:UnsafeMutableRawPointer?
    private var secure=false
    private(set) var active=false
    init(enable:@escaping ()->OSStatus = { EnableSecureEventInput() },
         disable:@escaping ()->OSStatus = { DisableSecureEventInput() },
         push:@escaping ()->UnsafeMutableRawPointer? = { PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled)) },
         pop:@escaping (UnsafeMutableRawPointer)->Void = { PopSymbolicHotKeyMode($0) }) {
        self.enable=enable;self.disable=disable;self.push=push;self.pop=pop
    }
    func begin() {
        guard !active else { return }
        active=true;secure=enable() == noErr;token=push()
    }
    func end() {
        guard active else { return }
        active=false
        if let token { pop(token);self.token=nil }
        if secure { _=disable();secure=false }
    }
    deinit { end() }
}

/// Encoding uses the same physical keys and grammar as shortcut output.
enum ShortcutCapture {
    static func encode(keyCode:UInt16,modifiers:NSEvent.ModifierFlags)->String? {
        guard (!modifiers.contains(.function) || MacShortcut.isFunctionKey(keyCode)),
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

/// Captures only while this field is in the key window. A temporary input tap
/// catches system shortcuts before macOS consumes them; no key events are logged.
final class ShortcutRecorder:NSControl {
    private(set) var shortcutValue:String?
    var changed:(()->Void)?
    private var monitor:Any?
    private var keyTap:CFMachPort?
    private var tapSource:CFRunLoopSource?
    private var keyWindowObserver:NSObjectProtocol?
    private var appObserver:NSObjectProtocol?
    private let inputPriority=ShortcutInputPriority()
    private var pendingKeyRelease:UInt16?
    private var finishingCapture=false
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
    deinit { stopListening() }
    /// Load a saved or suggested chord without treating it as a new key press.
    func setShortcut(_ value:String?) {
        recording=false;message="";stopListening()
        shortcutValue=value.flatMap { $0.isEmpty ? nil:$0 }
        updateAccessibility();needsDisplay=true
    }
    @objc func optionChanged(_ sender:Any?) { changed?() }
    private func listenWhileFocused() {
        guard NSApp.isActive,let window,window.isKeyWindow,window.firstResponder === self else { return }
        inputPriority.begin()
        if keyWindowObserver == nil {
            keyWindowObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:window,queue:.main) { [weak self] _ in self?.cancelRecording() }
            appObserver=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:NSApp,queue:.main) { [weak self] _ in self?.cancelRecording() }
        }
        if keyTap == nil {
            let mask=(CGEventMask(1)<<CGEventType.keyDown.rawValue)|(CGEventMask(1)<<CGEventType.keyUp.rawValue)|(CGEventMask(1)<<CGEventType.flagsChanged.rawValue)
            keyTap=CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{ _,type,event,context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner=Unmanaged<ShortcutRecorder>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap=owner.keyTap { CGEvent.tapEnable(tap:tap,enable:true) }
                    return Unmanaged.passUnretained(event)
                }
                guard NSApp.isActive,owner.window?.isKeyWindow == true,owner.window?.firstResponder === owner,
                      let captured=NSEvent(cgEvent:event) else { return Unmanaged.passUnretained(event) }
                return owner.intercept(captured) ? nil:Unmanaged.passUnretained(event)
            },userInfo:Unmanaged.passUnretained(self).toOpaque())
            if let keyTap {
                let source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,keyTap,0)
                tapSource=source;CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
                CFRunLoopAddSource(CFRunLoopGetMain(),source,CFRunLoopMode(rawValue:RunLoop.Mode.modalPanel.rawValue as CFString))
            }
        }
        guard monitor == nil else { return }
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]) { [weak self] event in
            guard let self,NSApp.isActive,self.window?.isKeyWindow == true,
                  self.window?.firstResponder === self else { return event }
            return self.intercept(event) ? nil:event
        }
    }
    /// Keep repeats, key-up, and modifier releases inside this capture as well.
    func intercept(_ event:NSEvent)->Bool {
        if finishingCapture {
            if event.type == .keyUp,event.keyCode == pendingKeyRelease { pendingKeyRelease=nil }
            // AppKit also marks ordinary F-key events with .function; it does
            // not necessarily mean the physical Fn modifier is still held.
            if pendingKeyRelease == nil,event.modifierFlags.intersection([.control,.option,.shift,.command]).isEmpty { stopListening() }
            return true
        }
        guard recording else { return false }
        if event.type == .keyDown { consume(event) }
        return true
    }
    private func cancelRecording() {
        recording=false;message="";stopListening();updateAccessibility();needsDisplay=true
    }
    private func stopListening() {
        pendingKeyRelease=nil;finishingCapture=false
        if let monitor { NSEvent.removeMonitor(monitor);self.monitor=nil }
        if let keyTap { CGEvent.tapEnable(tap:keyTap,enable:false);CFMachPortInvalidate(keyTap);self.keyTap=nil }
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),tapSource,.commonModes)
            CFRunLoopRemoveSource(CFRunLoopGetMain(),tapSource,CFRunLoopMode(rawValue:RunLoop.Mode.modalPanel.rawValue as CFString))
            self.tapSource=nil
        }
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver);self.keyWindowObserver=nil }
        if let appObserver { NotificationCenter.default.removeObserver(appObserver);self.appObserver=nil }
        inputPriority.end()
    }
    override func viewWillMove(toWindow newWindow:NSWindow?) {
        if newWindow !== window { cancelRecording() }
        super.viewWillMove(toWindow:newWindow)
    }
    override func mouseDown(with event:NSEvent) { beginRecording() }
    override func accessibilityPerformPress()->Bool { beginRecording();return true }
    private func beginRecording() {
        guard isEnabled else { return }
        guard let window,window.makeFirstResponder(self) else {
            message="Click again to focus this shortcut field.";needsDisplay=true;return
        }
        stopListening();recording=true;message="";listenWhileFocused();updateAccessibility();needsDisplay=true
    }
    override func becomeFirstResponder()->Bool {
        recording=true;message="";listenWhileFocused();updateAccessibility();needsDisplay=true
        DispatchQueue.main.async { [weak self] in
            guard let self,self.recording,self.window?.firstResponder === self else { return }
            self.listenWhileFocused();self.updateAccessibility()
        }
        return true
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
            recording=false;message="";finishingCapture=true;pendingKeyRelease=event.keyCode;updateAccessibility();needsDisplay=true;return
        }
        guard let value=ShortcutCapture.encode(keyCode:event.keyCode,modifiers:event.modifierFlags) else {
            message="Unsupported key. Try another shortcut.";needsDisplay=true;return
        }
        shortcutValue=value;recording=false;message="";finishingCapture=true;pendingKeyRelease=event.keyCode;updateAccessibility();needsDisplay=true
        changed?()
        sendAction(action,to:target)
    }
    private func updateAccessibility() {
        setAccessibilityValue(recording ? "Recording. Press shortcut keys.":shortcutValue.map(ShortcutCapture.display) ?? "No shortcut recorded")
        setAccessibilityHelp(recording && keyTap != nil
            ? "Press your shortcut. It will be captured here instead of performing its usual action."
            : "Click, then press the shortcut keys. Escape cancels recording. Tab moves to the next control.")
    }
    override func draw(_ dirtyRect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7)
        NSColor.controlBackgroundColor.setFill();shape.fill()
        (recording ? NSColor.rvAccent:NSColor.separatorColor).setStroke();shape.lineWidth=recording ? 2:1;shape.stroke()
        let title = !message.isEmpty ? message:recording ? "Press shortcut keys…":shortcutValue.map(ShortcutCapture.display) ?? "Click to record shortcut"
        let attributes:[NSAttributedString.Key:Any]=[.font:WorkspaceTypography.body(13,weight:shortcutValue != nil && !recording ? .semibold:.regular),.foregroundColor:recording ? NSColor.rvAccent:NSColor.labelColor]
        let text=title as NSString
        text.draw(at:NSPoint(x:12,y:bounds.midY-text.size(withAttributes:attributes).height/2),withAttributes:attributes)
        if shortcutValue != nil && !recording && message.isEmpty {
            let hint="Click to record" as NSString
            let style:[NSAttributedString.Key:Any]=[.font:WorkspaceTypography.body(11),.foregroundColor:NSColor.secondaryLabelColor]
            let size=hint.size(withAttributes:style)
            if text.size(withAttributes:attributes).width+size.width+40<bounds.width {
                hint.draw(at:NSPoint(x:bounds.maxX-size.width-12,y:bounds.midY-size.height/2),withAttributes:style)
            }
        }
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds,xRadius:7,yRadius:7).fill() }
    override var focusRingMaskBounds:NSRect { bounds }
}

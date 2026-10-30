import AppKit
import Darwin
import ApplicationServices
import IOKit.hid
import IOKit.hidsystem
import Carbon.HIToolbox

final class RemoteInput {
    private var manager: IOHIDManager?
    private(set) var generation=0
    private var pressed = Set<String>()
    var onDeliveredEdge:((Usage,Bool,Double?)->Void)?
    var onButtonValue:((Usage,Bool,Double?)->Void)?
    private static let millisecondsPerTick:Double = {
        var info=mach_timebase_info_data_t();mach_timebase_info(&info)
        return Double(info.numer)/Double(info.denom)/1_000_000
    }()
    var onOpenFailure:((IOReturn)->Void)?
    var onDevices: ((Int) -> Void)?
    var onDisconnected: (() -> Void)?
    private(set) var interfaceGroups = Set<InterfaceGroup>()
    private(set) var testButtonUsages=Set<Usage>()

    struct InterfaceGroup: Hashable { let page: Int; let usage: Int }
    static var allowed: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted || CGPreflightListenEventAccess() }
    static func requestPermission() { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    func start(_ profile: DeviceProfile,exclusive:Bool = false) throws {
        stop()
        guard Self.allowed else { throw JustVibeRemoteError.message("macOS has not approved this JustVibe Remote build for Input Monitoring. Open Connection check; restart after enabling access, or reset the old entry after an update.") }
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        manager = hid
        IOHIDManagerSetDeviceMatching(hid,[kIOHIDVendorIDKey:profile.vendorId,kIOHIDProductIDKey:profile.productId] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, result, _, device in
            guard let context else { return }
            let owner = Unmanaged<RemoteInput>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else { owner.onOpenFailure?(result);return }
            let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
            let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
            owner.interfaceGroups.insert(InterfaceGroup(page: page, usage: usage))
            owner.reportCount()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, _ in
            guard let context else { return }
            let owner = Unmanaged<RemoteInput>.fromOpaque(context).takeUnretainedValue()
            owner.pressed.removeAll()
            owner.onDisconnected?()
            owner.reportCount()
        }, context)
        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let owner = Unmanaged<RemoteInput>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let source = Usage(page: IOHIDElementGetUsagePage(element), code: IOHIDElementGetUsage(element))
            guard source.isButton else { return }
            // Interface identity prevents another interface's empty report from
            // releasing a held button. No input from unmatched devices is read.
            let identity = String(describing: IOHIDElementGetDevice(element)) + ":" + source.label
            let down = IOHIDValueGetIntegerValue(value) != 0
            let timestamp=IOHIDValueGetTimeStamp(value),now=mach_absolute_time()
            let lag:Double?=timestamp>0 && now>=timestamp ? Double(now-timestamp)*RemoteInput.millisecondsPerTick:nil
            owner.onButtonValue?(source,down,lag)
            if down {
                guard owner.pressed.insert(identity).inserted else { return }
            } else {
                guard owner.pressed.remove(identity) != nil else { return }
            }
            owner.onDeliveredEdge?(source,down,lag)
        }, context)
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(hid, exclusive ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice):0)
        guard result == kIOReturnSuccess else { stop(); throw JustVibeRemoteError.message("The receiver could not be opened\(exclusive ? " exclusively for test mode" : "") (\(String(format: "0x%08X", UInt32(bitPattern: result)))). Open Connection check for device and permission details.") }
        reportCount()
    }
    private func reportCount() {
        let devices = manager.flatMap { IOHIDManagerCopyDevices($0) as? Set<IOHIDDevice> } ?? []
        interfaceGroups=Set(devices.map { device in
            InterfaceGroup(page:(IOHIDDeviceGetProperty(device,kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0,
                           usage:(IOHIDDeviceGetProperty(device,kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0)
        })
        var usages=Set<Usage>()
        for device in devices {
            for element in IOHIDDeviceCopyMatchingElements(device,nil,0) as? [IOHIDElement] ?? [] {
                let type=IOHIDElementGetType(element)
                guard type == kIOHIDElementTypeInput_Button || type == kIOHIDElementTypeInput_ScanCodes || type == kIOHIDElementTypeInput_Misc else { continue }
                let usage=Usage(page:IOHIDElementGetUsagePage(element),code:IOHIDElementGetUsage(element))
                if usage.isButton || (usage.page == 7 && (0xE0...0xE7).contains(usage.code)) { usages.insert(usage) }
            }
        }
        testButtonUsages=usages
        onDevices?(devices.count)
    }
    func stop() {
        generation += 1
        let previous=manager;manager=nil
        if let manager=previous {
            IOHIDManagerRegisterDeviceMatchingCallback(manager,nil,nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager,nil,nil)
            IOHIDManagerRegisterInputValueCallback(manager,nil,nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        pressed.removeAll()
        interfaceGroups.removeAll();testButtonUsages.removeAll()
    }
}

struct MacShortcut {
    static let keyCodes: [String: CGKeyCode] = {
        var keys:[String:CGKeyCode] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46,"SPACE":49,"RETURN":36,"ENTER":36,"ESC":53,"BACKSPACE":51]
        let functions=[kVK_F1,kVK_F2,kVK_F3,kVK_F4,kVK_F5,kVK_F6,kVK_F7,kVK_F8,kVK_F9,kVK_F10,kVK_F11,kVK_F12,kVK_F13,kVK_F14,kVK_F15,kVK_F16,kVK_F17,kVK_F18,kVK_F19,kVK_F20]
        for (index,code) in functions.enumerated() { keys["F\(index+1)"]=CGKeyCode(code) }
        return keys
    }()
    static func isFunctionKey(_ code:CGKeyCode)->Bool {
        keyCodes.contains { $0.value == code && $0.key.hasPrefix("F") && Int($0.key.dropFirst()) != nil }
    }
    /// F-key events carry AppKit's function-key flag on both press and release,
    /// even when no physical Fn modifier is held.
    static func eventFlags(key:CGKeyCode,modifiers:CGEventFlags)->CGEventFlags {
        isFunctionKey(key) ? modifiers.union(.maskSecondaryFn):modifiers
    }
    let key: CGKeyCode
    let flags: CGEventFlags
    static func parse(_ text: String) throws -> MacShortcut {
        let pieces = text.uppercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let final = pieces.last, !pieces.contains("") else { throw JustVibeRemoteError.message("Enter a shortcut such as CTRL+SHIFT+D.") }

        guard let code = keyCodes[final] else { throw JustVibeRemoteError.message("Unsupported shortcut key. Use a letter, F1–F20, SPACE, RETURN, or ESC.") }
        var flags: CGEventFlags = []
        for item in pieces.dropLast() {
            switch item {
            case "CTRL", "CONTROL": flags.insert(.maskControl)
            case "SHIFT": flags.insert(.maskShift)
            case "ALT", "OPTION": flags.insert(.maskAlternate)
            case "CMD", "COMMAND": flags.insert(.maskCommand)
            default: throw JustVibeRemoteError.message("Unknown shortcut modifier: \(item)")
            }
        }
        return MacShortcut(key: code, flags: flags)
    }
}
struct SystemDictationKeyStroke:Equatable {
    let key:CGKeyCode
    let flags:CGEventFlags
    let type:CGEventType
    var release:SystemDictationKeyStroke? {
        if type == .keyDown { return SystemDictationKeyStroke(key:key,flags:MacShortcut.eventFlags(key:key,modifiers:[]),type:.keyUp) }
        if type == .flagsChanged && !flags.isEmpty { return SystemDictationKeyStroke(key:key,flags:[],type:.flagsChanged) }
        return nil
    }
}
enum SystemDictationKeyPlan {
    static func events(_ setting:SystemDictationSettings) throws -> [SystemDictationKeyStroke] {
        func twice(_ key:Int,_ flags:CGEventFlags)->[SystemDictationKeyStroke] {
            let down=SystemDictationKeyStroke(key:CGKeyCode(key),flags:flags,type:.flagsChanged)
            return [down,down.release!,down,down.release!]
        }
        switch setting.shortcutKind {
        case .controlTwice:return twice(kVK_Control,[.maskControl,CGEventFlags(rawValue:UInt64(NX_DEVICELCTLKEYMASK))])
        case .globeTwice:return twice(kVK_Function,.maskSecondaryFn)
        case .rightCommandTwice:return twice(kVK_RightCommand,[.maskCommand,CGEventFlags(rawValue:UInt64(NX_DEVICERCMDKEYMASK))])
        case .leftCommandTwice,.eitherCommandTwice:return twice(kVK_Command,[.maskCommand,CGEventFlags(rawValue:UInt64(NX_DEVICELCMDKEYMASK))])
        case .microphone:
            // Apple's documented Fn+D Dictation command; no private media-key code.
            let fn=SystemDictationKeyStroke(key:CGKeyCode(kVK_Function),flags:.maskSecondaryFn,type:.flagsChanged)
            return [fn,SystemDictationKeyStroke(key:CGKeyCode(kVK_ANSI_D),flags:.maskSecondaryFn,type:.keyDown),SystemDictationKeyStroke(key:CGKeyCode(kVK_ANSI_D),flags:.maskSecondaryFn,type:.keyUp),fn.release!]
        case .custom:
            let chord=try MacShortcut.parse(setting.shortcut)
            return [SystemDictationKeyStroke(key:chord.key,flags:MacShortcut.eventFlags(key:chord.key,modifiers:chord.flags),type:.keyDown),SystemDictationKeyStroke(key:chord.key,flags:MacShortcut.eventFlags(key:chord.key,modifiers:[]),type:.keyUp)]
        }
    }
}
/// A short, cancellable sequence. Modifier gestures need real spacing, while
/// the main queue must stay free to process a remote stop or a focus change.
final class SystemDictationKeySequence {
    private var generation=0
    private var releases:[SystemDictationKeyStroke]=[]
    private(set) var postedAny=false
    func start(_ events:[SystemDictationKeyStroke],schedule:@escaping (TimeInterval,@escaping ()->Void)->Void,
               post:@escaping (SystemDictationKeyStroke)throws->Void,failed:@escaping (Error)->Void) throws {
        generation+=1
        try emit(events,index:0,ticket:generation,schedule:schedule,post:post,failed:failed)
    }
    private func emit(_ events:[SystemDictationKeyStroke],index:Int,ticket:Int,schedule:@escaping (TimeInterval,@escaping ()->Void)->Void,
                      post:@escaping (SystemDictationKeyStroke)throws->Void,failed:@escaping (Error)->Void) throws {
        guard ticket == generation,events.indices.contains(index) else { return }
        let event=events[index];try post(event);postedAny=true
        releases.removeAll { $0.key == event.key }
        if let release=event.release { releases.append(release) }
        if index+1<events.count {
            schedule(0.05) { [weak self] in
                do { try self?.emit(events,index:index+1,ticket:ticket,schedule:schedule,post:post,failed:failed) }
                catch { failed(error) }
            }
        }
    }
    func cancel(post:(SystemDictationKeyStroke)throws->Void) throws {
        generation+=1
        while let event=releases.last { try post(event);releases.removeLast() }
    }
}
struct SingleShortcutTap {
    private(set) var complete=false
    private(set) var pendingKeyUp=false
    mutating func send(down:()throws->Void,up:()throws->Void) throws {
        guard !complete else { return }
        if !pendingKeyUp { try down();pendingKeyUp=true }
        try up();pendingKeyUp=false;complete=true
    }
}
/// Retain the process instance even when Launch Services has no launch date.
/// Its termination state prevents cleanup from targeting a reused process ID.
protocol ToggleShortcutApplication:AnyObject {
    var processIdentifier:pid_t { get }
    var isTerminated:Bool { get }
    var bundleIdentifier:String? { get }
    var launchDate:Date? { get }
}
extension NSRunningApplication:ToggleShortcutApplication {}
struct ToggleShortcutTarget {
    private let application:any ToggleShortcutApplication
    init?(_ application:any ToggleShortcutApplication,foregroundPID:pid_t?) {
        guard !application.isTerminated,application.processIdentifier == foregroundPID else { return nil }
        self.application=application
    }
    func liveApplication(resolve:(pid_t)->(any ToggleShortcutApplication)? = { NSRunningApplication(processIdentifier:$0) }) -> (any ToggleShortcutApplication)? {
        guard !application.isTerminated,
              let current=resolve(application.processIdentifier),
              !current.isTerminated,current.bundleIdentifier == application.bundleIdentifier,
              current.launchDate == application.launchDate else { return nil }
        return current
    }
}
final class TargetOutput {
    // Kept injectable so launch requests can be verified without opening apps.
    var openApplication: (URL,NSWorkspace.OpenConfiguration,@escaping (Error?)->Void)->Void = { url,options,completion in
        NSWorkspace.shared.openApplication(at:url,configuration:options) { _,error in completion(error) }
    }

    var plugin: AppPlugin?
    private var heldShortcut: MacShortcut?
    private var toggleLease=ToggleShortcutLease()
    private var toggleShortcut:MacShortcut?
    private var toggleTarget:ToggleShortcutTarget?
    private var systemSequence:SystemDictationKeySequence?
    private var systemTarget:ToggleShortcutTarget?
    private var systemStop=SingleShortcutTap()
    var voiceFailure:((Error)->Void)?
    var hasVoiceOutput:Bool { heldShortcut != nil || toggleLease.active || systemTarget != nil }
    func beginDictation(_ config:Configuration,operation:String) throws {
        if config.usesSystemDictation { try beginSystemDictation(config);return }
        guard operation == "toggle-shortcut" else { try hold(config.shortcut);return }
        guard !hasVoiceOutput else { return }
        guard let app=target(config),
              let target=ToggleShortcutTarget(app,foregroundPID:NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            throw JustVibeRemoteError.message("Bring the selected app to the front before starting dictation.")
        }
        let shortcut=try MacShortcut.parse(config.shortcut)
        toggleTarget=target;toggleShortcut=shortcut
        var lease=toggleLease
        defer { toggleLease=lease }
        let destination=Self.toggleEventPID(target:app.processIdentifier,foreground:NSWorkspace.shared.frontmostApplication?.processIdentifier)
        do {
            try lease.start(down:{try self.post(shortcut.key,flags:shortcut.flags,down:true,pid:destination)},up:{try self.post(shortcut.key,flags:[],down:false,pid:destination)})
        } catch {
            if !lease.active { toggleTarget=nil;toggleShortcut=nil }
            throw error
        }
    }
    private func releaseToggle() throws {
        guard let target=toggleTarget,let shortcut=toggleShortcut else { return }
        guard let app=target.liveApplication() else {
            toggleLease=ToggleShortcutLease();toggleTarget=nil;toggleShortcut=nil;return
        }
        var lease=toggleLease
        defer { toggleLease=lease }
        let destination=Self.toggleEventPID(target:app.processIdentifier,foreground:NSWorkspace.shared.frontmostApplication?.processIdentifier)
        // Native app toggles retain the configured start/stop chord.
        let stop=try Self.dictationStopShortcut(start:shortcut,system:false)
        try lease.stop(down:{try self.post(stop.key,flags:stop.flags,down:true,pid:destination)},up:{try self.post(stop.key,flags:[],down:false,pid:destination)},releaseStart:{try self.post(shortcut.key,flags:[],down:false,pid:destination)})
        toggleTarget=nil;toggleShortcut=nil
    }
    private func beginSystemDictation(_ config:Configuration) throws {
        guard !hasVoiceOutput else { return }
        guard let setting=config.systemDictation[config.devicePluginID],setting.enabled,
              let app=target(config),let target=ToggleShortcutTarget(app,foregroundPID:NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            throw JustVibeRemoteError.message("Bring your text app to the front before starting macOS Dictation.")
        }
        try setting.validate()
        let events=try SystemDictationKeyPlan.events(setting),sequence=SystemDictationKeySequence()
        systemTarget=target;systemSequence=sequence;systemStop=SingleShortcutTap()
        try sequence.start(events,schedule:{ delay,work in DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work) },post:{ [weak self] event in
            guard let self,let live=target.liveApplication(),NSWorkspace.shared.frontmostApplication?.processIdentifier == live.processIdentifier else {
                throw JustVibeRemoteError.message("The active app changed. Press the microphone button again in your text app.")
            }
            try self.post(event.key,flags:event.flags,down:event.type == .keyDown,eventType:event.type)
        },failed:{ [weak self] error in self?.voiceFailure?(error) })
    }
    private func releaseSystemDictation() throws {
        guard let target=systemTarget else { return }
        // Modifier-up events are safe globally and must not leave Fn/Ctrl/Cmd held.
        try systemSequence?.cancel { event in try self.post(event.key,flags:event.flags,down:false,eventType:event.type) }
        if systemSequence?.postedAny == true,let app=target.liveApplication() {
            let pid=Self.toggleEventPID(target:app.processIdentifier,foreground:NSWorkspace.shared.frontmostApplication?.processIdentifier)
            try systemStop.send(down:{try self.post(53,flags:[],down:true,pid:pid)},up:{try self.post(53,flags:[],down:false,pid:pid)})
        }
        systemSequence=nil;systemTarget=nil;systemStop=SingleShortcutTap()
    }
    static func dictationStopShortcut(start:MacShortcut,system:Bool) throws -> MacShortcut {
        system ? try MacShortcut.parse("ESC"):start
    }
    /// Foreground shortcuts use the normal keyboard event path, as held
    /// dictation already does. After focus loss, cleanup must stay addressed to
    /// the original process instead of toggling voice in the newly focused app.
    /// Resolve once per tap so key-down and key-up use the same destination.
    static func toggleEventPID(target:pid_t,foreground:pid_t?) -> pid_t? {
        foreground == target ? nil : target
    }
    static var allowed: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func target(_ config: Configuration) -> NSRunningApplication? {
        if config.usesSystemDictation {
            return config.systemDictationTargetPID.flatMap { NSRunningApplication(processIdentifier:$0) }
        }
        if config.appPluginID == Configuration.noSpecificAppID { return NSWorkspace.shared.frontmostApplication }
        func matches(_ app: NSRunningApplication) -> Bool {
            if !config.targetAppPath.isEmpty { return app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: config.targetAppPath).standardizedFileURL.path }
            guard let target = plugin?.targets["macos"] else { return false }
            return target.bundleIds.contains(app.bundleIdentifier ?? "") || target.names.contains(app.localizedName ?? "")
        }
        if let front = NSWorkspace.shared.frontmostApplication, matches(front) { return front }
        return NSWorkspace.shared.runningApplications.first(where: matches)
    }
    func isTargetFrontmost(_ config: Configuration) -> Bool {
        guard let target = target(config) else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }
    func show(_ config: Configuration,completion:((Error?)->Void)? = nil) throws {
        if config.appPluginID == Configuration.noSpecificAppID { return }
        let url:URL?
        if let runningURL=target(config)?.bundleURL { url=runningURL }
        else if !config.targetAppPath.isEmpty { url=URL(fileURLWithPath:config.targetAppPath) }
        else { url=plugin?.targets["macos"]?.bundleIds.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }.first }
        guard let url else {
            throw JustVibeRemoteError.message("Open the selected app first, or choose its application in JustVibe Remote.")
        }
        // A remote press explicitly requests a foreground switch, including
        // when another app is active. Basic NSRunningApplication.activate can
        // leave an already-running target in the background in that case.
        let options=NSWorkspace.OpenConfiguration()
        options.activates=true;options.hides=false;options.createsNewApplicationInstance=false
        options.allowsRunningApplicationSubstitution=false
        openApplication(url,options) { error in completion?(error) }
    }

    func hold(_ text: String) throws {
        guard heldShortcut == nil else { return }
        let shortcut = try MacShortcut.parse(text)
        try post(shortcut.key, flags: shortcut.flags, down: true)
        heldShortcut = shortcut
    }
    func release() throws {
        if systemTarget != nil { try releaseSystemDictation();return }
        if toggleLease.active { try releaseToggle();return }
        guard let shortcut = heldShortcut else { return }
        try post(shortcut.key, flags: [], down: false)
        heldShortcut = nil
    }
    func tap(_ action: RemoteAction) throws {
        guard let plugin else { throw JustVibeRemoteError.message("Select an app plugin first") }
        let shortcut = try MacShortcut.parse(plugin.shortcut(action))
        try post(shortcut.key, flags: shortcut.flags, down: true)
        try post(shortcut.key, flags: [], down: false)
    }
    private func post(_ key: CGKeyCode, flags: CGEventFlags, down: Bool,pid:pid_t?=nil,eventType:CGEventType?=nil) throws {
        guard Self.allowed else { throw JustVibeRemoteError.message("Accessibility permission is required to send shortcuts. No shortcut was sent.") }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else {
            throw JustVibeRemoteError.message("macOS could not create the keyboard event.")
        }
        event.flags = MacShortcut.eventFlags(key:key,modifiers:flags)
        if let eventType { event.type=eventType }
        event.setIntegerValueField(.eventSourceUserData, value: 0x5256_4942)
        if let pid { event.postToPid(pid) }
        else { event.post(tap: .cghidEventTap) }
    }
}

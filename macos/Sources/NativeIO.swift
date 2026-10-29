import AppKit
import Darwin
import ApplicationServices
import IOKit.hid

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
        interfaceGroups.removeAll()
    }
}

struct MacShortcut {
    static let keyCodes: [String: CGKeyCode] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46,"SPACE":49,"RETURN":36,"ENTER":36,"ESC":53,"BACKSPACE":51]
    let key: CGKeyCode
    let flags: CGEventFlags
    static func parse(_ text: String) throws -> MacShortcut {
        let pieces = text.uppercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let final = pieces.last, !pieces.contains("") else { throw JustVibeRemoteError.message("Enter a shortcut such as CTRL+SHIFT+D.") }

        guard let code = keyCodes[final] else { throw JustVibeRemoteError.message("Unsupported shortcut key. Use a letter, SPACE, RETURN, or ESC.") }
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
/// Retain the process instance, including when Launch Services has no launch
/// date (as can happen for Cursor). The retained instance's termination state
/// prevents cleanup from being redirected to a later process reusing its PID.
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
    var plugin: AppPlugin?
    private var heldShortcut: MacShortcut?
    private var toggleLease=ToggleShortcutLease()
    private var toggleShortcut:MacShortcut?
    private var toggleTarget:ToggleShortcutTarget?
    var hasVoiceOutput:Bool { heldShortcut != nil || toggleLease.active }
    func beginDictation(_ config:Configuration,operation:String) throws {
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
        try lease.stop(down:{try self.post(shortcut.key,flags:shortcut.flags,down:true,pid:destination)},up:{try self.post(shortcut.key,flags:[],down:false,pid:destination)})
        toggleTarget=nil;toggleShortcut=nil
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
    func show(_ config: Configuration) throws {
        if config.appPluginID == Configuration.noSpecificAppID { return }
        if let app = target(config) {
            app.activate(options: [])
        } else if !config.targetAppPath.isEmpty {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: config.targetAppPath), configuration: NSWorkspace.OpenConfiguration())
        } else if let url = plugin?.targets["macos"]?.bundleIds.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            throw JustVibeRemoteError.message("Open the selected app first, or choose its application in JustVibe Remote.")
        }
    }
    func hold(_ text: String) throws {
        guard heldShortcut == nil else { return }
        let shortcut = try MacShortcut.parse(text)
        try post(shortcut.key, flags: shortcut.flags, down: true)
        heldShortcut = shortcut
    }
    func release() throws {
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
    private func post(_ key: CGKeyCode, flags: CGEventFlags, down: Bool,pid:pid_t?=nil) throws {
        guard Self.allowed else { throw JustVibeRemoteError.message("Accessibility permission is required to send shortcuts. No shortcut was sent.") }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else {
            throw JustVibeRemoteError.message("macOS could not create the keyboard event.")
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: 0x5256_4942)
        if let pid { event.postToPid(pid) }
        else { event.post(tap: .cghidEventTap) }
    }
}

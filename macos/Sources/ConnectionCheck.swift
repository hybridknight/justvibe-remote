import AppKit
import ApplicationServices
import IOKit.hid

struct ReceiverInterface: Codable {
    let name: String
    let page: Int
    let usage: Int
}
struct ConnectionReport: Codable {
    let appPath: String
    let version: String
    let inputMonitoring: Bool
    let hidPermission: Int32
    let eventListenPermission: Bool
    let accessibility: Bool
    let hardwareID: String
    let interfaces: [ReceiverInterface]
    let openResult: Int32?
    let state: ConnectionState
    static func collect(_ profile: DeviceProfile, probe: Bool = true) -> ConnectionReport {
        let hid = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let event = CGPreflightListenEventAccess()
        let input = hid == kIOHIDAccessTypeGranted || event
        let accessibility = AXIsProcessTrusted()
        var iterator: io_iterator_t = 0
        var interfaces: [ReceiverInterface] = []
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                func property(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() }
                if (property("VendorID") as? NSNumber)?.intValue == profile.vendorId && (property("ProductID") as? NSNumber)?.intValue == profile.productId {
                    interfaces.append(ReceiverInterface(name:property("Product") as? String ?? "HID remote",page:(property("PrimaryUsagePage") as? NSNumber)?.intValue ?? 0,usage:(property("PrimaryUsage") as? NSNumber)?.intValue ?? 0))
                }
            }
        }
        var result: IOReturn?
        // A short, non-seizing open/close. No value callbacks, button capture, audio, or output.
        if probe && input && !interfaces.isEmpty {
            let manager = IOHIDManagerCreate(kCFAllocatorDefault,0)
            IOHIDManagerSetDeviceMatching(manager,[kIOHIDVendorIDKey:profile.vendorId,kIOHIDProductIDKey:profile.productId] as CFDictionary)
            result = IOHIDManagerOpen(manager,0)
            IOHIDManagerClose(manager,0)
        }
        return ConnectionReport(appPath:Bundle.main.bundleURL.path,version:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown",inputMonitoring:input,hidPermission:Int32(hid.rawValue),eventListenPermission:event,accessibility:accessibility,hardwareID:profile.hardwareID,interfaces:interfaces,openResult:result,state:ConnectionState.resolve(inputAllowed:input,shortcutsAllowed:accessibility,interfaces:interfaces.count,openResult:result))
    }
    var summary: String {
        switch state {
        case .inputPermission: return "macOS is not allowing this build to read remote buttons."
        case .shortcutPermission: return "Remote access is approved. This build still needs Accessibility for app shortcuts."
        case .receiverMissing: return "Permissions are approved, but the selected remote is not detected. Connect its USB receiver or pair it in Bluetooth settings."
        case .openFailed: return "The receiver is detected, but macOS could not open it."
        case .ready: return "The selected receiver is detected and its connection can be opened."
        }
    }
    var details: String {
        "Input Monitoring: \(inputMonitoring ? "allowed" : "not allowed for this build")\nAccessibility: \(accessibility ? "allowed" : "not allowed for this build")\nReceiver \(hardwareID): \(interfaces.count) HID interfaces detected\nDevice connection: \(openResult.map { $0 == 0 ? "opened successfully" : String(format:"failed (0x%08X)",UInt32(bitPattern:$0)) } ?? "not attempted")\nApp version: \(version)\nApp to approve: \(appPath)"
    }
}

final class ConnectionCheck: NSObject, NSWindowDelegate {
    private let controller: RemoteController
    private weak var parent: NSWindow?
    private let panel: NSPanel
    private let summary = NSTextField(wrappingLabelWithString:"")
    private let details = NSTextField(wrappingLabelWithString:"")
    private let message = NSTextField(wrappingLabelWithString:"")
    private var ended = false
    var finished: (() -> Void)?
    init(controller: RemoteController, parent: NSWindow) {
        self.controller=controller; self.parent=parent
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:700,height:620),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init();panel.title="Connection check";panel.delegate=self;panel.isReleasedWhenClosed=false;panel.appearance=NSAppearance(named:.aqua)
        let root=NSView();root.wantsLayer=true;root.layer?.backgroundColor=NSColor.white.cgColor;panel.contentView=root
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:24)])
        summary.font = .systemFont(ofSize:21,weight:.bold);stack.addArrangedSubview(summary)
        details.font = .systemFont(ofSize:12);details.isSelectable=true;stack.addArrangedSubview(details)
        let help=NSTextField(wrappingLabelWithString:"If a permission switch is already on, quit and reopen JustVibe Remote. Older builds changed signature on every update. After moving to a persistent signer, replace the old approval once. Reset only the affected entry below, then enable this exact app build in Settings and restart.");help.font = .systemFont(ofSize:12);stack.addArrangedSubview(help)
        func button(_ title:String,_ action:Selector)->NSButton { NSButton(title:title,target:self,action:action) }
        stack.addArrangedSubview(NSStackView(views:[button("Check again",#selector(refresh)),button("Show this app in Finder",#selector(reveal)),button("Restart JustVibe Remote",#selector(restart))]))
        stack.addArrangedSubview(NSStackView(views:[button("Open Input Monitoring",#selector(openInput)),button("Open Accessibility",#selector(openAccessibility))]))
        let resetHelp=NSTextField(wrappingLabelWithString:"Reset removes only JustVibe Remote’s permission for the selected category. macOS will require your approval again. Your saved buttons, microphone choice, and plugins are kept.");resetHelp.font = .systemFont(ofSize:11);resetHelp.textColor = .secondaryLabelColor;stack.addArrangedSubview(resetHelp)
        stack.addArrangedSubview(NSStackView(views:[button("Reset Input Monitoring entry",#selector(resetInput)),button("Reset Accessibility entry",#selector(resetAccessibility))]))
        message.font = .systemFont(ofSize:12);stack.addArrangedSubview(message);stack.addArrangedSubview(button("Close",#selector(close)))
        refresh()
    }
    func show() { parent?.beginSheet(panel) }
    func render(to url:URL) throws {
        guard let view=panel.contentView else{return};view.layoutSubtreeIfNeeded()
        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]){try png.write(to:url)}}
    }
    @objc private func refresh() { let report=ConnectionReport.collect(controller.config.profile);summary.stringValue=report.summary;details.stringValue=report.details }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    private func privacy(_ anchor:String) { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?\(anchor)")!) }
    @objc private func openInput() { RemoteInput.requestPermission();privacy("Privacy_ListenEvent") }
    @objc private func openAccessibility() { TargetOutput.requestPermission();privacy("Privacy_Accessibility") }
    @objc private func resetInput() { reset("ListenEvent",anchor:"Privacy_ListenEvent") }
    @objc private func resetAccessibility() { reset("Accessibility",anchor:"Privacy_Accessibility") }
    private func reset(_ service:String,anchor:String) {
        do {
            try controller.stop()
            let task=Process(),pipe=Pipe();task.executableURL=URL(fileURLWithPath:"/usr/bin/tccutil");task.arguments=["reset",service,Bundle.main.bundleIdentifier!];task.standardOutput=pipe;task.standardError=pipe
            try task.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw JustVibeRemoteError.message(String(data:data,encoding:.utf8) ?? "macOS could not reset this entry.") }
            message.stringValue="Entry reset. In Settings, add this exact app using + (or drag it from Finder), enable it, then click Restart JustVibe Remote."
            privacy(anchor);refresh()
        } catch { message.stringValue=error.localizedDescription }
    }
    @objc private func restart() { do { try controller.restartApp() } catch { message.stringValue=error.localizedDescription } }
    @objc private func close() { guard !ended else{return};ended=true;parent?.endSheet(panel);panel.orderOut(nil);finished?() }
    func windowShouldClose(_ sender:NSWindow)->Bool { close();return false }
}

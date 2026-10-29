import Foundation
import Darwin
import IOKit.hidsystem

/// Writes only the selected receiver's HID mouse service, never the HID system.
final class CursorSpeedControl {
    private let client=IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private let bootSession: String
    private let journal: URL
    private var leases: [CursorLease]
    private var profile: DeviceProfile?
    private var desired: CursorSpeedSettings?
    private var lastService: UInt64?
    private var previewing=false
    private var lastPoll=Date.distantPast
    private(set) var status="System cursor behavior"
    init(directory: URL) throws {
        var size=0
        guard sysctlbyname("kern.bootsessionuuid",nil,&size,nil,0)==0,size>1 else { throw JustVibeRemoteError.message("Cannot identify this macOS session for safe cursor restoration.") }
        var bytes=[CChar](repeating:0,count:size)
        guard sysctlbyname("kern.bootsessionuuid",&bytes,&size,nil,0)==0 else { throw JustVibeRemoteError.message("Cannot identify this macOS session for safe cursor restoration.") }
        bootSession=String(cString:bytes)
        journal=directory.appendingPathComponent("cursor-speed-leases.json")
        leases=FileManager.default.fileExists(atPath:journal.path) ? try JSONDecoder().decode([CursorLease].self,from:Data(contentsOf:journal)) : []
        guard leases.count <= 64 else { throw JustVibeRemoteError.message("Cursor restoration journal is invalid; it was preserved.") }
    }
    private var services: [IOHIDServiceClient] { IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? [] }
    private func number(_ service:IOHIDServiceClient,_ key:String)->NSNumber? { IOHIDServiceClientCopyProperty(service,key as CFString) as? NSNumber }
    private func registryID(_ service:IOHIDServiceClient)->UInt64 { (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0 }
    private func matches(_ service:IOHIDServiceClient,vendor:Int,product:Int)->Bool {
        number(service,"VendorID")?.intValue == vendor && number(service,"ProductID")?.intValue == product && IOHIDServiceClientConformsTo(service,1,2) != 0
    }
    private func target(_ profile:DeviceProfile)throws->IOHIDServiceClient {
        let matches=services.filter { self.matches($0,vendor:profile.vendorId,product:profile.productId) }
        guard matches.count == 1 else { throw JustVibeRemoteError.message(matches.isEmpty ? "Connect the selected remote’s USB receiver and turn on cursor mode." : "More than one matching remote pointer is connected. Disconnect the other receiver before changing speed.") }
        guard IOHIDServiceClientCopyProperty(matches[0],"HIDPointerAccelerationType" as CFString) as? String == "HIDMouseAcceleration",number(matches[0],"HIDMouseAcceleration") != nil,registryID(matches[0]) != 0 else { throw JustVibeRemoteError.message("This receiver does not expose supported remote-only speed control. Other mice were not changed.") }
        return matches[0]
    }
    func current(_ profile:DeviceProfile)throws->Double { Double(number(try target(profile),"HIDMouseAcceleration")!.int32Value)/65536 }
    func currentLinear(_ profile:DeviceProfile)throws->Bool { try current(profile)<0 }
    private func persist()throws {
        try FileManager.default.createDirectory(at:journal.deletingLastPathComponent(),withIntermediateDirectories:true)
        let data=try JSONEncoder().encode(leases);try data.write(to:journal,options:.atomic)
    }
    private func set(_ service:IOHIDServiceClient,value:Int32)throws {
        guard IOHIDServiceClientSetProperty(service,"HIDMouseAcceleration" as CFString,NSNumber(value:value)),number(service,"HIDMouseAcceleration")?.int32Value == value else { throw JustVibeRemoteError.message("macOS rejected the remote-only cursor setting. Other mice were not changed.") }
    }
    private func apply(_ profile:DeviceProfile,_ setting:CursorSpeedSettings)throws {
        try setting.validate();let service=try target(profile),id=registryID(service)
        let before=number(service,"HIDMouseAcceleration")!.int32Value
        let previous=leases.first { $0.registryID == id && $0.belongsTo(boot:bootSession) }
        leases.removeAll { $0.registryID == id }
        leases.append(CursorLease(bootSession:bootSession,registryID:id,vendorID:profile.vendorId,productID:profile.productId,original:previous.flatMap { $0.shouldRestore(current:before) ? $0.original : nil } ?? before,applied:setting.fixed))
        try persist()
        do { try set(service,value:setting.fixed) }
        catch {
            let originalError=error
            if number(service,"HIDMouseAcceleration")?.int32Value == setting.fixed {
                do { try set(service,value:before) } catch { throw JustVibeRemoteError.message("Cursor change failed and needs restoration. Reopen Cursor setup or restart JustVibe Remote.") }
            }
            leases.removeAll { $0.registryID == id };if let previous { leases.append(previous) };try persist();throw originalError
        }
        lastService=id;status="Remote-only cursor speed active"
    }
    func restore()throws {
        let current=services
        for index in leases.indices.reversed() {
            let lease=leases[index]
            if lease.belongsTo(boot:bootSession),let service=current.first(where:{registryID($0)==lease.registryID && matches($0,vendor:lease.vendorID,product:lease.productID)}) {
                guard let value=number(service,"HIDMouseAcceleration")?.int32Value else { throw JustVibeRemoteError.message("Cannot read the remote’s current speed. Restoration was preserved for retry.") }
                if lease.shouldRestore(current:value) { try set(service,value:lease.original) }
            }
            // A removed HID service no longer has an active setting to restore.
            // A changed value belongs to the user or another utility and is preserved.
            leases.remove(at:index);try persist()
        }
        lastService=nil;status="System cursor behavior"
    }
    func configure(profile:DeviceProfile,setting:CursorSpeedSettings?)throws {
        previewing=false
        if self.profile?.id != profile.id || self.profile?.hardwareID != profile.hardwareID { try restore() }
        self.profile=profile;desired=setting
        if let setting,setting.enabled { try apply(profile,setting) }
        else { try restore() }
    }
    func preview(profile:DeviceProfile,setting:CursorSpeedSettings)throws { try apply(profile,setting);previewing=true }
    func finishPreview()throws {
        guard previewing else{return};previewing=false
        if let profile,let setting=desired,setting.enabled {
            guard let service=try? target(profile) else { try restore();status="Receiver unavailable; unsaved preview cleared";return }
            let id=registryID(service)
            if let lease=leases.first(where:{$0.registryID==id}),let current=number(service,"HIDMouseAcceleration")?.int32Value,!lease.shouldRestore(current:current) { try restore();lastService=id;status="External cursor settings preserved";return }
            try apply(profile,setting)
        } else { try restore() }
    }
    func poll() {
        guard !previewing,let profile,let desired,desired.enabled,Date().timeIntervalSince(lastPoll)>1 else{return}
        lastPoll=Date()
        do {
            let service=try target(profile),id=registryID(service)
            guard id != lastService else{return}
            try restore();lastService=id;try apply(profile,desired)
        } catch { status=error.localizedDescription }
    }
}

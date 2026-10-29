import Foundation
import IOKit.hidsystem
@main struct CursorNativeChecks {
 static func main() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("justviberemote-cursor-check-"+UUID().uuidString)
    let client=IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    func otherPointers()->[String:String] {
        var result=[String:String]()
        for s in IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? [] where IOHIDServiceClientConformsTo(s,1,2) != 0 {
            let vendor=(IOHIDServiceClientCopyProperty(s,"VendorID" as CFString) as? NSNumber)?.intValue
            let product=(IOHIDServiceClientCopyProperty(s,"ProductID" as CFString) as? NSNumber)?.intValue
            if vendor==0x1915 && product==0x1025 { continue }
            for key in ["HIDMouseAcceleration","HIDUseLinearScalingMouseAcceleration"] {
                result["\(IOHIDServiceClientGetRegistryID(s))/\(key)"]=String(describing:IOHIDServiceClientCopyProperty(s,key as CFString))
            }
        };return result
    }
    let beforeOthers=otherPointers()
    let profile=DeviceProfile(id:"verification",name:"XING WEI",vendorId:0x1915,productId:0x1025)
    let control=try CursorSpeedControl(directory:directory)
    let speed=try control.current(profile),linear=try control.currentLinear(profile)
    let curve=speed<0 ? 0.6875 : speed
    defer { try? control.restore() }
    for mode in [!linear,linear] {
        try control.preview(profile:profile,setting:CursorSpeedSettings(level:curve,linear:mode))
        guard try control.currentLinear(profile)==mode,try control.current(profile)==(mode ? -1 : curve) else { throw NSError(domain:"CursorVerification",code:1,userInfo:[NSLocalizedDescriptionKey:"Native mode/speed readback mismatch"]) }
    }
    try control.restore()
    // Old speed-only preferences must regain their mode after a bypass preview.
    try control.configure(profile:profile,setting:CursorSpeedSettings(level:curve))
    try control.preview(profile:profile,setting:CursorSpeedSettings(level:curve,linear:true))
    try control.finishPreview()
    guard try control.current(profile)==curve else { throw NSError(domain:"CursorVerification",code:3) }
    try control.restore()
    // Recover the original value from a fresh control after an interrupted session.
    try control.preview(profile:profile,setting:CursorSpeedSettings(level:curve,linear:true))
    let recovered=try CursorSpeedControl(directory:directory)
    try recovered.configure(profile:profile,setting:nil)
    guard try control.currentLinear(profile)==linear,try control.current(profile)==speed,otherPointers()==beforeOthers else { throw NSError(domain:"CursorVerification",code:2,userInfo:[NSLocalizedDescriptionKey:"Native restoration/isolation mismatch"]) }
    try FileManager.default.removeItem(at:directory)
    print("Native receiver check passed: acceleration bypass/curve readback, legacy preview cancellation, crash-journal recovery, original value restored, other pointer settings unchanged.")
 }
}

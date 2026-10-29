import Foundation

struct CursorSpeedSettings: Codable, Equatable {
    var level: Double
    var enabled: Bool = true
    // nil preserves the native mode for settings saved before linear tracking existed.
    var linear: Bool? = nil
    func validate() throws {
        guard level.isFinite, (0...3).contains(level) else { throw JustVibeRemoteError.message("Cursor speed must be between the supported native levels.") }
    }
    var fixed: Int32 { linear == true ? -65536 : Int32((level * 65536).rounded()) }
}
struct CursorLease: Codable {
    let bootSession: String
    let registryID: UInt64
    let vendorID: Int
    let productID: Int
    let original: Int32
    var applied: Int32
    /// Preserve settings changed outside JustVibe Remote; restore only a value we own.
    func shouldRestore(current: Int32) -> Bool { current == applied }
    func belongsTo(boot: String) -> Bool { !boot.isEmpty && bootSession == boot }
}

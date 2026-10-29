import Foundation

enum ConnectionState: String, Codable {
    case inputPermission, shortcutPermission, receiverMissing, openFailed, ready
    static func resolve(inputAllowed: Bool, shortcutsAllowed: Bool, interfaces: Int, openResult: Int32?) -> ConnectionState {
        if !inputAllowed { return .inputPermission }
        if !shortcutsAllowed { return .shortcutPermission }
        if interfaces == 0 { return .receiverMissing }
        if let openResult, openResult != 0 { return .openFailed }
        return .ready
    }
}

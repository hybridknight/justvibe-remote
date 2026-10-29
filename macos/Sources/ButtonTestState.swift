import Foundation

/// Transient presentation state. It never changes mappings or app preferences.
struct ButtonTestState {
    static func shouldEnable(buttonsPageVisible:Bool,appActive:Bool,windowVisible:Bool,windowMiniaturized:Bool)->Bool {
        buttonsPageVisible && appActive && windowVisible && !windowMiniaturized
    }
    private(set) var enabled=false
    private(set) var lastUsage:Usage?
    private var flashes:[Usage:TimeInterval]=[:]
    mutating func setEnabled(_ value:Bool) {
        enabled=value;lastUsage=nil;flashes.removeAll()
    }
    mutating func observe(_ usage:Usage,down:Bool,now:TimeInterval) {
        guard enabled else { return }
        if down { lastUsage=usage;flashes[usage]=now+0.4 }
    }
    func highlights(active:Set<Usage>,now:TimeInterval)->Set<Usage> {
        guard enabled else { return active }
        return active.union(flashes.filter { $0.value>now }.map(\.key))
    }
}

/// A failed exclusive test must restore normal listening before reporting testing unavailable.
enum ButtonTestCapture {
    static func transition(enabled:Bool,reopen:(Bool)throws->Void)throws->String? {
        do { try reopen(enabled);return nil }
        catch {
            guard enabled else { throw error }
            let failure=error.localizedDescription
            try reopen(false)
            return failure
        }
    }
}

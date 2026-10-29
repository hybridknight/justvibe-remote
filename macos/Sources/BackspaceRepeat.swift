import Foundation

/// One repeat per tick: a stalled input loop must never replay a burst of deletes.
struct BackspaceRepeat {
    private(set) var usage:Usage?
    private var nextAt=0.0
    mutating func start(_ usage:Usage,now:TimeInterval) { self.usage=usage;nextAt=now+0.4 }
    mutating func release(_ usage:Usage) { if self.usage==usage { cancel() } }
    mutating func cancel() { usage=nil }
    mutating func due(now:TimeInterval)->Bool {
        guard usage != nil,now>=nextAt else{return false}
        nextAt=now+0.06;return true
    }
}

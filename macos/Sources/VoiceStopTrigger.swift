import Foundation

/// Stop is owned by the input that started the session, even if routing changes.
struct VoiceStopTrigger {
    let usage:Usage
    let mode:String
    func shouldStop(usage:Usage,down:Bool,active:Bool)->Bool {
        active && self.usage==usage && (mode=="toggle" ? down : !down)
    }
}

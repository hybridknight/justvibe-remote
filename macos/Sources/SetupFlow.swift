import Foundation

enum SetupShortcut {
    /// An old, unconfirmed default should not override the plugin's current suggestion.
    /// Confirmed custom keys remain authoritative; this is only an editable setup draft.
    static func initialValue(saved:String,confirmed:Bool,suggested:String?) -> String {
        guard !confirmed,let suggested,!suggested.isEmpty else { return saved }
        return suggested
    }
}

enum SetupStep: String {
    case inputPermission, shortcutPermission, receiver, microphone, shortcut, test, ready
}
struct SetupProgress {
    var inputAllowed: Bool
    var shortcutsAllowed: Bool
    var receiverConnected: Bool
    var needsDictation: Bool
    var microphoneLinked: Bool
    var shortcutConfirmed: Bool
    var testConfirmed: Bool
    var step: SetupStep {
        if !inputAllowed { return .inputPermission }
        if !shortcutsAllowed { return .shortcutPermission }
        if !receiverConnected { return .receiver }
        if !needsDictation { return .ready }
        if !microphoneLinked { return .microphone }
        if !shortcutConfirmed { return .shortcut }
        if !testConfirmed { return .test }
        return .ready
    }
}

/// The welcome journey has five visible milestones. Voice is optional, and
/// completing the journey requires the user's report of a successful try-out.
enum RemoteSetupStage: String, Codable, CaseIterable {
    case welcome, app, permissions, receiver, button, microphone, shortcut, practice, done
    var milestone: Int {
        switch self {
        case .welcome: return 0
        case .app: return 1
        case .permissions, .receiver: return 2
        case .button, .microphone, .shortcut: return 3
        case .practice, .done: return 4
        }
    }
    func next(voice: Bool) -> Self {
        switch self {
        case .welcome: return .app
        case .app: return .permissions
        case .permissions: return .receiver
        case .receiver: return voice ? .microphone : .button
        case .button: return voice ? .microphone : .practice
        case .microphone: return .shortcut
        case .shortcut: return .practice
        case .practice, .done: return .done
        }
    }
    func previous(voice: Bool) -> Self {
        switch self {
        case .welcome: return .welcome
        case .app: return .welcome
        case .permissions: return .app
        case .receiver: return .permissions
        case .button: return .receiver
        case .microphone: return .receiver
        case .shortcut: return .microphone
        case .practice: return voice ? .shortcut : .button
        case .done: return .practice
        }
    }
}
struct RemoteSetupCheckpoint: Codable, Equatable {
    var stage: RemoteSetupStage = .welcome
    var wantsVoice = true
    var controlID: String?
    func resuming(appAvailable: Bool, inputAllowed: Bool, shortcutsAllowed: Bool, connected: Bool) -> Self {
        var next=self
        guard stage != .welcome && stage != .done else { return next }
        if !appAvailable { next.stage = .app }
        else if stage != .app && (!inputAllowed || !shortcutsAllowed) { next.stage = .permissions }
        else if stage.milestone > 2 && !connected { next.stage = .receiver }
        else if stage == .button && wantsVoice { next.stage = .microphone }
        return next
    }
}

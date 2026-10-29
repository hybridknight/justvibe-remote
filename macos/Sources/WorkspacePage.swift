import AppKit

/// Navigation is presentation-only; changing pages never changes the active profile.
enum WorkspacePage: String, CaseIterable {
    case remotes, overview, apps, buttons, voice, devices, plugins, help
    var isRemoteScoped: Bool { [.overview, .apps, .buttons, .voice, .devices].contains(self) }
    var index: Int { Self.allCases.firstIndex(of:self)! }
    var title: String {
        switch self {
        case .remotes: return "Remotes"
        case .plugins: return "Plugins"
        case .overview: return "Overview"
        case .buttons: return "Buttons"
        case .voice: return "Microphone test"
        case .apps: return "Apps"
        case .devices: return "Remote settings"
        case .help: return "Help & setup"
        }
    }
    var sidebarTitle: String {
        switch self {
        case .voice: return "Microphone"
        case .devices: return "Settings"
        default: return title
        }
    }
    var subtitle: String {
        switch self {
        case .remotes: return "Start with a remote, then configure its apps and buttons."
        case .plugins: return "Browse installed support for your remotes and apps."
        case .overview: return "Set up this remote, then choose its apps and button actions."
        case .buttons: return "Choose a button, link it, then pick what it does."
        case .voice: return "Check the audio from your remote."
        case .apps: return "Apps supported by this remote."
        case .devices: return "Connection, cursor, and behavior settings for this remote."
        case .help: return "Guided setup and troubleshooting, when you need them."
        }
    }
    var symbol: String {
        switch self {
        case .remotes: return "appletvremote.gen4"
        case .plugins: return "puzzlepiece.extension"
        case .overview: return "square.grid.2x2"
        case .buttons: return "circle.grid.2x2"
        case .voice: return "waveform"
        case .apps: return "app"
        case .devices: return "slider.horizontal.3"
        case .help: return "questionmark.circle"
        }
    }
}

/// A flipped document keeps short forms at the top of their scroll view.
final class WorkspaceDocument: NSView {
    override var isFlipped: Bool { true }
}

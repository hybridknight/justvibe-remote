import Foundation

struct LayoutRect: Codable, Equatable {
    let x: Double; let y: Double; let width: Double; let height: Double
}
struct LayoutDisc: Codable, Equatable { let x: Double; let y: Double; let radius: Double }
struct LayoutControl: Codable, Equatable {
    let id: String
    let label: String
    let icon: String
    let shape: String
    let bounds: LayoutRect
    let text: String?
    let hint: String?
    let usage: Usage?
    let defaultAction: RemoteAction?
}
struct RemoteLayout: Codable, Equatable {
    let version: Int
    let width: Double
    let height: Double
    let bodyStyle: String
    let description: String?
    let dpad: LayoutDisc?
    let buttons: [LayoutControl]
    static let icons = Set(["power", "mode", "microphone", "up", "down", "left", "right", "ok", "home-back", "home", "back", "menu", "volume-up", "volume-down", "page-up", "page-down", "apps", "label"])
    func validate() throws {
        func require(_ value: Bool) throws { if !value { throw JustVibeRemoteError.message("Invalid remote layout: use unique controls with finite, in-bounds geometry and supported icons.") } }
        try require(version == 1 && width.isFinite && height.isFinite && (100...2000).contains(width) && (100...2000).contains(height))
        try require(["silver", "dark"].contains(bodyStyle) && (1...48).contains(buttons.count) && Set(buttons.map(\.id)).count == buttons.count)
        try require((description?.count ?? 0) <= 400)
        if let dpad {
            try require(dpad.x.isFinite && dpad.y.isFinite && dpad.radius.isFinite && dpad.radius > 0 && dpad.x - dpad.radius >= 0 && dpad.y - dpad.radius >= 0 && dpad.x + dpad.radius <= width && dpad.y + dpad.radius <= height)
        }
        try require(Set(buttons.compactMap(\.usage)).count == buttons.compactMap(\.usage).count)
        for control in buttons {
            let b = control.bounds
            try require(control.id.range(of: #"^[a-z][a-z0-9._-]{0,47}$"#, options: .regularExpression) != nil)
            try require(!control.label.isEmpty && control.label.count <= 60 && Self.icons.contains(control.icon) && ["circle", "pill", "rounded", "segment"].contains(control.shape))
            try require([b.x,b.y,b.width,b.height].allSatisfy(\.isFinite) && b.x >= 0 && b.y >= 0 && b.width >= 16 && b.height >= 16 && b.x + b.width <= width && b.y + b.height <= height)
            try require((control.text?.count ?? 0) <= 20 && (control.hint?.count ?? 0) <= 300 && (control.usage == nil || (control.usage!.isButton && control.usage!.page <= 65535 && control.usage!.code <= 65535)))
        }
    }
    /// Keep previously learned controls by stable ID, then legacy name. Unknown
    /// legacy bindings remain accessible from the inspector instead of vanishing.
    func bindings(preserving old: [Binding] = []) throws -> [Binding] {
        var used = Set<Int>()
        var result = buttons.map { control -> Binding in
            if let index = old.indices.first(where: { !used.contains($0) && (old[$0].controlID == control.id || old[$0].name.caseInsensitiveCompare(control.label) == .orderedSame || (control.id == "back" && old[$0].name == "Back")) }) {
                used.insert(index)
                var binding = old[index]; binding.controlID = control.id; binding.name = control.label
                return binding
            }
            return Binding(name: control.label, usage: control.usage, action: control.defaultAction ?? .native, controlID: control.id)
        }
        let retained = old.indices.filter { !used.contains($0) }
        guard result.count + retained.count <= 64 else { throw JustVibeRemoteError.message("This layout upgrade would exceed 64 controls. Existing bindings are preserved; keep stable control IDs or simplify the layout.") }
        for index in retained { result.append(old[index]) }
        return result
    }
    static func generic(_ bindings: [Binding]) -> RemoteLayout {
        let buttons = bindings.enumerated().map { index, binding in
            LayoutControl(id: binding.controlID ?? "button-\(index)", label: binding.name, icon: binding.action == .dictate ? "microphone" : "label", shape: "rounded", bounds: LayoutRect(x: Double(25 + index % 2 * 110), y: Double(70 + index / 2 * 80), width: 80, height: 52), text: String(binding.name.prefix(12)), hint: nil, usage: nil, defaultAction: nil)
        }
        return RemoteLayout(version: 1, width: 240, height: max(640, Double(100 + (bindings.count + 1) / 2 * 80)), bodyStyle: "dark", description: "Generic layout. Device plugins can supply a photo-based layout.", dpad: nil, buttons: buttons)
    }
}

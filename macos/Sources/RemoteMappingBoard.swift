import AppKit

/// Mapping cards and their connectors derive from the same layout as the remote.
/// A plugin supplies geometry; it never supplies executable UI or drawing code.
final class RemoteMappingBoard: NSView {
    override var isFlipped: Bool { true }
    private let canvas:RemoteCanvas
    private let connections=MappingConnections()
    private var model:RemoteLayout?
    private var cards:[MappingCard]=[]
    private var selectedID:String?
    var selected:((String)->Void)?
    var assigned:((String,RemoteAction)->Void)?
    var learn:((String)->Void)?
    var cancelLearning:(()->Void)?

    init(canvas:RemoteCanvas) {
        self.canvas=canvas;super.init(frame:.zero)
        addSubview(canvas);addSubview(connections)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(layout:RemoteLayout,bindings:[Binding],selection:String?,actions:[RemoteAction],learningID:String?,active:Set<Usage>,dictationShortcut:String = "",launchAppNames:[String:String] = [:],currentAppID:String = "") {
        if model != layout {
            cards.forEach { $0.removeFromSuperview() };model=layout
            cards=layout.buttons.sorted { a,b in a.bounds.y == b.bounds.y ? a.bounds.x<b.bounds.x:a.bounds.y<b.bounds.y }.map { control in
                let card=MappingCard(control:control)
                card.selected={ [weak self] in self?.selected?(control.id) }
                card.assigned={ [weak self] action in self?.assigned?(control.id,action) }
                card.link={ [weak self] cancel in if cancel { self?.cancelLearning?() } else { self?.learn?(control.id) } }
                addSubview(card,positioned:.below,relativeTo:connections);return card
            }
        }
        selectedID=selection
        for card in cards {
            let binding=bindings.first { $0.controlID == card.control.id || (card.control.id.hasPrefix("button-") && $0.name == card.control.label) }
            card.update(binding:binding,dictationShortcut:dictationShortcut,launchAppName:launchAppNames[binding?.launchAppID ?? currentAppID],selected:selection == card.control.id,actions:actions,learning:learningID == card.control.id,otherLearning:learningID != nil && learningID != card.control.id,live:binding?.usage.map { active.contains($0) } ?? false)
        }
        needsLayout=true
    }
    override func layout() {
        super.layout();guard let model else { return }
        var left:[MappingCard]=[],right:[MappingCard]=[]
        for card in cards {
            let center=card.control.bounds.x+card.control.bounds.width/2
            if abs(center-model.width/2)<1 {
                if left.count<=right.count { left.append(card) } else { right.append(card) }
            } else if center<model.width/2 { left.append(card) } else { right.append(card) }
        }
        let height=bounds.height
        let rows=max(1,max(left.count,right.count))
        let rowPitch=min(60,max(1,(height-24)/CGFloat(rows)))
        let cardHeight=max(1,rowPitch-6)
        let centerWidth=min(220,max(140,bounds.width*0.23))
        let cardWidth=max(1,(bounds.width-centerWidth-40)/2)
        canvas.frame=NSRect(x:(bounds.width-centerWidth)/2,y:12,width:centerWidth,height:max(1,height-24))
        canvas.layoutSubtreeIfNeeded()
        var lines:[MappingConnections.Line]=[]
        for (list,isLeft) in [(left,true),(right,false)] {
            for (index,card) in list.enumerated() {
                card.frame=NSRect(x:isLeft ? 0:bounds.width-cardWidth,y:12+CGFloat(index)*rowPitch,width:cardWidth,height:cardHeight)
                if let point=canvas.center(of:card.control.id) {
                    lines.append(.init(start:convert(point,from:canvas),end:NSPoint(x:isLeft ? card.frame.maxX:card.frame.minX,y:card.frame.midY),chosen:card.control.id == selectedID))
                }
            }
        }
        connections.frame=bounds;connections.lines=lines;connections.needsDisplay=true

    }
}

private final class MappingConnections:NSView {
    struct Line { let start:NSPoint;let end:NSPoint;let chosen:Bool }
    var lines:[Line]=[]
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        for line in lines.sorted(by: { !$0.chosen && $1.chosen }) {
            let path=NSBezierPath();path.move(to:line.start)
            let bend=(line.end.x-line.start.x)*0.55
            path.curve(to:line.end,controlPoint1:NSPoint(x:line.start.x+bend,y:line.start.y),controlPoint2:NSPoint(x:line.end.x-bend*0.4,y:line.end.y))
            (line.chosen ? NSColor.rvAccent:NSColor.rvMuted.withAlphaComponent(0.25)).setStroke()
            path.lineWidth=line.chosen ? 2:0.8;path.stroke()
            if line.chosen {
                NSColor.rvAccent.setFill();NSBezierPath(ovalIn:NSRect(x:line.start.x-3,y:line.start.y-3,width:6,height:6)).fill()
                let direction:CGFloat=line.end.x>line.start.x ? 1:-1
                let arrow=NSBezierPath();arrow.move(to:line.end);arrow.line(to:NSPoint(x:line.end.x-direction*6,y:line.end.y-4));arrow.line(to:NSPoint(x:line.end.x-direction*6,y:line.end.y+4));arrow.close();arrow.fill()
            }
        }
    }
}

private final class MappingCard:NSView {
    let control:LayoutControl
    private let name=NSButton(),picker=NSPopUpButton(),linkButton=NSButton()
    private var actions:[RemoteAction]=[]
    private var menuTitles:[String]=[]
    private var learning=false
    var selected:(()->Void)?
    var assigned:((RemoteAction)->Void)?
    var link:((Bool)->Void)?
    override var isFlipped:Bool { true }
    init(control:LayoutControl) {
        self.control=control;super.init(frame:.zero);wantsLayer=true
        layer?.cornerRadius=12;layer?.borderWidth=1
        name.title=control.label;name.isBordered=false;name.alignment = .left;name.font = WorkspaceTypography.body(12,weight:.semibold)
        name.target=self;name.action=#selector(choose);name.setAccessibilityLabel("Select \(control.label)")
        name.cell?.lineBreakMode = .byTruncatingTail;name.toolTip=control.hint ?? control.label
        linkButton.isBordered=false;linkButton.font = WorkspaceTypography.body(11,weight:.medium);linkButton.target=self;linkButton.action=#selector(linkControl)
        picker.controlSize = .small;picker.font = WorkspaceTypography.body(11);picker.target=self;picker.action=#selector(assign)
        picker.setAccessibilityLabel("Action when pressing \(control.label)")
        for view in [name,picker,linkButton] { addSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(binding:Binding?,dictationShortcut:String,launchAppName:String?,selected:Bool,actions:[RemoteAction],learning:Bool,otherLearning:Bool,live:Bool) {
        self.learning=learning
        layer?.backgroundColor=(live ? NSColor.systemTeal.withAlphaComponent(0.12):selected ? NSColor.rvAccent.withAlphaComponent(0.08):NSColor.white).cgColor
        layer?.borderColor=(live ? NSColor.systemTeal:selected ? NSColor.rvAccent:NSColor.rvBorder).cgColor
        layer?.borderWidth=selected || live ? 1.5:1
        name.contentTintColor=live ? .systemTeal:selected ? .rvAccent:.rvInk
        name.setAccessibilityValue(selected ? "Selected":"")
        let titles=actions.map { action in
            action == .focus && binding?.action == .focus ? "Open app · \(launchAppName ?? "Choose app…")" : action == .dictate && !dictationShortcut.isEmpty ? "Dictation · \(dictationShortcut)" : action.title
        }
        if menuTitles != titles { self.actions=actions;menuTitles=titles;picker.removeAllItems();picker.addItems(withTitles:titles) }
        picker.selectItem(at:actions.firstIndex(of:binding?.action ?? .native) ?? 0)
        picker.isEnabled = !learning && !otherLearning
        linkButton.title=learning ? "Cancel":binding?.usage == nil ? "Link":"Relink"
        linkButton.contentTintColor=learning ? .systemOrange:.rvMuted
        linkButton.isEnabled = !otherLearning
        linkButton.setAccessibilityLabel(learning ? "Cancel learning \(control.label)":"\(linkButton.title) \(control.label)")
        toolTip=learning ? "Press \(control.label) on your physical remote…":binding?.usage == nil ? "Signal not linked. Choose Link, then press this button on your remote.":"Linked · \(control.label)"
    }
    override func layout() {
        super.layout()
        let compact=bounds.height<48
        name.frame=NSRect(x:10,y:2,width:max(30,bounds.width-68),height:compact ? 17:20)
        linkButton.frame=NSRect(x:bounds.width-57,y:2,width:49,height:compact ? 17:20)
        picker.frame=NSRect(x:9,y:compact ? 18:25,width:max(1,bounds.width-18),height:compact ? 20:24)
    }
    @objc private func choose() { selected?() }
    @objc private func assign() { let i=picker.indexOfSelectedItem;guard actions.indices.contains(i) else { return };assigned?(actions[i]) }
    @objc private func linkControl() { link?(learning) }
}

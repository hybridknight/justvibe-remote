import AppKit

/// Status rows are read-only checks. Permissions still change only through
/// the explicit action button and macOS settings.
final class SetupChecklistRow: NSView {
    private let icon=NSImageView()
    private let status=NSTextField(labelWithString:"")
    private let action:NSButton
    private let title:String
    init(title:String,detail:String,actionTitle:String,target:AnyObject,selector:Selector) {
        self.title=title;action=NSButton(title:actionTitle,target:target,action:selector)
        super.init(frame:.zero)
        wantsLayer=true;layer?.cornerRadius=14;layer?.borderWidth=1
        let name=NSTextField(labelWithString:title);name.font = .systemFont(ofSize:15,weight:.semibold);name.textColor = .rvInk
        let description=NSTextField(wrappingLabelWithString:detail);description.font = .systemFont(ofSize:12);description.textColor = .rvMuted;description.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let words=NSStackView(views:[name,description]);words.orientation = .vertical;words.alignment = .leading;words.spacing=5
        words.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        icon.widthAnchor.constraint(equalToConstant:30).isActive=true;icon.heightAnchor.constraint(equalToConstant:30).isActive=true
        status.font = .systemFont(ofSize:12,weight:.semibold);status.textColor = .systemGreen
        action.bezelStyle = .rounded;action.controlSize = .large
        let space=NSView();space.setContentHuggingPriority(.init(1),for:.horizontal)
        let row=NSStackView(views:[icon,words,space,status,action]);row.spacing=13;row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints=false;addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),row.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),row.topAnchor.constraint(equalTo:topAnchor,constant:18),row.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-18),heightAnchor.constraint(greaterThanOrEqualToConstant:86)])
        setCompleted(false)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    func setCompleted(_ completed:Bool) {
        icon.image=NSImage(systemSymbolName:completed ? "checkmark.circle.fill":"circle",accessibilityDescription:completed ? "Completed":"Not completed")
        icon.contentTintColor=completed ? .systemGreen:.rvMuted
        status.stringValue="Allowed";status.isHidden = !completed;action.isHidden=completed
        layer?.backgroundColor=(completed ? NSColor.systemGreen.withAlphaComponent(0.05):NSColor(white:0.98,alpha:1)).cgColor
        layer?.borderColor=(completed ? NSColor.systemGreen.withAlphaComponent(0.22):NSColor.rvMuted.withAlphaComponent(0.16)).cgColor
        setAccessibilityLabel("\(title): \(completed ? "Allowed":"Needs permission")")
    }
}

final class SetupMilestoneView: NSView {
    private let icon=NSImageView()
    private let label:NSTextField
    init(title:String) {
        label=NSTextField(labelWithString:title);super.init(frame:.zero)
        icon.widthAnchor.constraint(equalToConstant:20).isActive=true;icon.heightAnchor.constraint(equalToConstant:20).isActive=true
        let row=NSStackView(views:[icon,label]);row.spacing=9;row.translatesAutoresizingMaskIntoConstraints=false;addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:leadingAnchor),row.trailingAnchor.constraint(equalTo:trailingAnchor),row.topAnchor.constraint(equalTo:topAnchor),row.bottomAnchor.constraint(equalTo:bottomAnchor)])
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    func update(completed:Bool,current:Bool) {
        icon.image=NSImage(systemSymbolName:completed ? "checkmark.circle.fill":current ? "circle.inset.filled":"circle",accessibilityDescription:completed ? "Completed":current ? "Current step":"Upcoming step")
        icon.contentTintColor=completed ? .systemGreen:current ? .rvAccent:.rvMuted.withAlphaComponent(0.5)
        label.textColor=current ? .rvAccent:completed ? .rvInk:.rvMuted
        label.font = .systemFont(ofSize:12,weight:current ? .semibold:.regular)
    }
}

/// Large native checkmark with a progress ring. It only becomes a completed
/// green check when all required items have actually been granted.
final class SetupCheckmarkArtwork: NSView {
    override var isFlipped:Bool { true }
    var completed=0 { didSet { if oldValue != completed { needsDisplay=true } } }
    var total=2 { didSet { needsDisplay=true } }
    override func draw(_ dirtyRect:NSRect) {
        let all=total>0 && completed>=total
        let tint:NSColor=all ? .systemGreen:.rvAccent
        let center=NSPoint(x:bounds.midX,y:bounds.midY)
        let radius=min(bounds.width,bounds.height)*0.39
        let circle=NSBezierPath(ovalIn:NSRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2))
        tint.withAlphaComponent(all ? 0.12:0.06).setFill();circle.fill()
        tint.withAlphaComponent(0.14).setStroke();circle.lineWidth=7;circle.stroke()
        let fraction=total>0 ? min(1,max(0,Double(completed)/Double(total))):0
        if fraction>0 {
            tint.setStroke();let arc=NSBezierPath();arc.appendArc(withCenter:center,radius:radius,startAngle:-90,endAngle:CGFloat(-90+360*fraction),clockwise:false);arc.lineWidth=7;arc.lineCapStyle = .round;arc.stroke()
        }
        let check=NSBezierPath();check.move(to:NSPoint(x:center.x-radius*0.43,y:center.y-radius*0.02));check.line(to:NSPoint(x:center.x-radius*0.09,y:center.y+radius*0.3));check.line(to:NSPoint(x:center.x+radius*0.46,y:center.y-radius*0.35))
        (all ? tint:NSColor.rvMuted.withAlphaComponent(0.28)).setStroke();check.lineWidth=12;check.lineCapStyle = .round;check.lineJoinStyle = .round;check.stroke()
    }
}

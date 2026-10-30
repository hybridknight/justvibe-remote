import AppKit

extension NSColor {
    static let rvAccent = NSColor(srgbRed: 0.36, green: 0.32, blue: 0.88, alpha: 1)
    static let rvInk = NSColor(srgbRed: 0.14, green: 0.16, blue: 0.23, alpha: 1)
    static let rvMuted = NSColor(srgbRed: 0.40, green: 0.44, blue: 0.53, alpha: 1)
}

final class RemoteCanvas: NSView {
    override var isFlipped: Bool { true }
    private var remoteLayout: RemoteLayout?
    private var controls: [RemoteGraphicButton] = []
    var isInteractive=true
    var testing=false
    var selected: ((String) -> Void)?
    func update(layout: RemoteLayout, bindings: [Binding], selection: String?, active: Set<Usage>) {
        if remoteLayout != layout {
            controls.forEach { $0.removeFromSuperview() }
            remoteLayout = layout
            controls = layout.buttons.map { item in
                let button = RemoteGraphicButton(control: item)
                button.target = self; button.action = #selector(selectButton(_:))
                addSubview(button)
                return button
            }
            needsLayout = true
        }
        for button in controls {
            let binding = bindings.first { $0.controlID == button.control.id || (button.control.id.hasPrefix("button-") && $0.name == button.control.label) }
            button.isEnabled=isInteractive
            button.setAccessibilityHelp(testing ? "Select this button, then press its physical counterpart to link and test an unlinked signal.":isInteractive ? "Select this physical button to learn its signal and change its action.":"Press this button on your physical remote to see it light up.")
            button.chosen = button.control.id == selection
            button.learned = binding?.usage != nil
            button.live = binding?.usage.map { active.contains($0) } ?? false
            button.toolTip = "\(button.control.label) · \(binding?.usage == nil ? "Not learned" : "Linked")" + (testing ? " · Click to select for testing":isInteractive ? " · Click to configure":"")
            button.needsDisplay = true
        }
        needsDisplay = true
    }
    private var transform: (CGFloat, CGFloat, CGFloat) {
        guard let model = remoteLayout else { return (1,0,0) }
        let scale = min((bounds.width - 52)/model.width, (bounds.height - 28)/model.height)
        return (max(0.1,scale),(bounds.width-model.width*scale)/2,(bounds.height-model.height*scale)/2)
    }
    func center(of controlID:String)->NSPoint? {
        guard let control=remoteLayout?.buttons.first(where: { $0.id == controlID }) else { return nil }
        let (scale,x,y)=transform
        return NSPoint(x:x+(control.bounds.x+control.bounds.width/2)*scale,y:y+(control.bounds.y+control.bounds.height/2)*scale)
    }
    override func layout() {
        super.layout()
        let (scale,x,y) = transform
        for button in controls {
            let b = button.control.bounds
            button.frame = NSRect(x: x+b.x*scale, y: y+b.y*scale, width: b.width*scale, height: b.height*scale)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let model = remoteLayout else { return }
        let (scale,x,y) = transform
        NSGraphicsContext.saveGraphicsState()
        let matrix = NSAffineTransform(); matrix.translateX(by: x, yBy: y); matrix.scale(by: scale); matrix.concat()
        let body = NSBezierPath(roundedRect: NSRect(x:0,y:0,width:model.width,height:model.height),xRadius:18,yRadius:18)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.17); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width:0,height:8); shadow.set()
        NSColor(white:0.45,alpha:1).setFill(); body.fill()
        NSGraphicsContext.restoreGraphicsState()
        let metal: [NSColor] = model.bodyStyle == "silver" ? [.init(white:0.32,alpha:1),.init(white:0.85,alpha:1),.init(white:0.62,alpha:1),.init(white:0.79,alpha:1),.init(white:0.32,alpha:1)] : [.init(white:0.16,alpha:1),.init(white:0.23,alpha:1),.init(white:0.13,alpha:1)]
        NSGradient(colors:metal)?.draw(in:body,angle:0)
        NSColor(white:0.12,alpha:1).setStroke();body.lineWidth=2;body.stroke()
        let face = NSBezierPath(roundedRect:NSRect(x:18,y:30,width:model.width-36,height:min(model.height-60,528)),xRadius:25,yRadius:25)
        NSGradient(starting:NSColor(white:0.13,alpha:1),ending:NSColor(white:0.07,alpha:1))?.draw(in:face,angle:90)
        if let d = model.dpad {
            let ring = NSBezierPath(ovalIn:NSRect(x:d.x-d.radius,y:d.y-d.radius,width:d.radius*2,height:d.radius*2))
            NSGradient(starting:NSColor(white:0.25,alpha:1),ending:NSColor(white:0.15,alpha:1))?.draw(in:ring,angle:90)
            NSColor.black.withAlphaComponent(0.45).setStroke();ring.lineWidth=2;ring.stroke()
        }
        let logo = "JUSTVIBEREMOTE" as NSString
        let attrs: [NSAttributedString.Key:Any] = [.font:WorkspaceTypography.body(11,weight:.semibold),.foregroundColor:NSColor.black.withAlphaComponent(0.3),.kern:3]
        let size=logo.size(withAttributes:attrs)
        logo.draw(at:NSPoint(x:(model.width-size.width)/2,y:model.height-65),withAttributes:attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
    @objc private func selectButton(_ sender: RemoteGraphicButton) { selected?(sender.control.id) }
}

private final class RemoteGraphicButton: NSButton {
    let control: LayoutControl
    var chosen=false; var learned=false; var live=false
    private var hovered=false
    override var isFlipped: Bool { true }
    init(control: LayoutControl) {
        self.control=control; super.init(frame:.zero)
        isBordered=false; title=""; bezelStyle = .regularSquare
        setAccessibilityLabel(control.label)
        setAccessibilityHelp("Select this physical button to learn its signal and change its action.")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func mouseEntered(with event:NSEvent) { hovered=true;needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false;needsDisplay=true }
    override func draw(_ dirtyRect:NSRect) {
        let rect=bounds.insetBy(dx:2,dy:2)
        let radius=control.shape == "circle" || control.shape == "pill" ? min(rect.width,rect.height)/2 : 7
        let path=NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius)
        let bright=chosen || live || isHighlighted
        if bright { (live ? NSColor.systemTeal : .rvAccent).setFill();path.fill() }
        else if control.shape == "pill" { NSColor(white:0.96,alpha:1).setFill();path.fill() }
        else if control.shape != "segment" || hovered {
            NSGradient(starting:NSColor(white:hovered ? 0.28:0.23,alpha:1),ending:NSColor(white:0.13,alpha:1))?.draw(in:path,angle:90)
        }
        if chosen { NSColor(srgbRed:0.73,green:0.77,blue:1,alpha:1).setStroke();path.lineWidth=2;path.stroke() }
        else if control.shape != "segment" { NSColor.black.withAlphaComponent(0.22).setStroke();path.lineWidth=1;path.stroke() }
        let color:NSColor=bright ? .white : control.shape == "pill" ? .rvInk : control.icon == "power" ? .systemRed : control.icon == "microphone" ? NSColor(srgbRed:0.55,green:0.65,blue:1,alpha:1) : .white
        if control.icon == "microphone" {
            let w=rect.width*0.22, cx=rect.midX, cy=rect.midY
            let capsule=NSBezierPath(roundedRect:NSRect(x:cx-w/2,y:cy-w*1.1,width:w,height:w*1.5),xRadius:w/2,yRadius:w/2)
            color.setStroke();capsule.lineWidth=1.6;capsule.stroke()
            let stand=NSBezierPath();stand.move(to:NSPoint(x:cx-w*0.85,y:cy-w*0.25));stand.curve(to:NSPoint(x:cx+w*0.85,y:cy-w*0.25),controlPoint1:NSPoint(x:cx-w*0.85,y:cy+w*1.1),controlPoint2:NSPoint(x:cx+w*0.85,y:cy+w*1.1));stand.move(to:NSPoint(x:cx,y:cy+w*0.7));stand.line(to:NSPoint(x:cx,y:cy+w*1.25));stand.move(to:NSPoint(x:cx-w*0.45,y:cy+w*1.25));stand.line(to:NSPoint(x:cx+w*0.45,y:cy+w*1.25));stand.lineWidth=1.6;stand.stroke()
        } else {
            let glyphs=["power":"⏻","mode":"◎","up":"▴","down":"▾","left":"◂","right":"▸","ok":"OK","home-back":"⌂↶","home":"⌂","back":"↶","menu":"≡","volume-up":"V +","volume-down":"V −","page-up":"PG +","page-down":"PG −","apps":"▦ Apps"]
            let text=(control.text ?? glyphs[control.icon] ?? control.label) as NSString
            let size:CGFloat=control.shape == "pill" ? max(7,min(11,rect.width/7)) : ["ok","home-back","volume-up","volume-down","page-up","page-down"].contains(control.icon) ? max(8,min(12,rect.width/4)) : max(12,min(24,rect.height*0.65))
            let attrs:[NSAttributedString.Key:Any]=[.font:WorkspaceTypography.body(size,weight:.semibold),.foregroundColor:color]
            let measure=text.size(withAttributes:attrs)
            text.draw(at:NSPoint(x:rect.midX-measure.width/2,y:rect.midY-measure.height/2),withAttributes:attrs)
        }
        if learned && !chosen && control.shape != "segment" { NSColor.systemMint.setFill();NSBezierPath(ovalIn:NSRect(x:rect.maxX-6,y:rect.maxY-6,width:4,height:4)).fill() }
    }
}

final class PrimaryButton: NSButton {
    override var intrinsicContentSize: NSSize {
        let size=(title as NSString).size(withAttributes:[.font:WorkspaceTypography.body(13,weight:.semibold)])
        return NSSize(width:max(120,size.width+28),height:38)
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect=bounds.insetBy(dx:1,dy:1)
        let shape=NSBezierPath(roundedRect:rect,xRadius:10,yRadius:10)
        let base=NSColor.rvAccent.withAlphaComponent(isEnabled ? isHighlighted ? 0.82:1:0.45)
        NSGradient(starting:base.blended(withFraction:0.12,of:.white) ?? base,ending:base)?.draw(in:shape,angle:90)
        NSColor.white.withAlphaComponent(0.15).setStroke();shape.lineWidth=1;shape.stroke()
        let attributes:[NSAttributedString.Key:Any]=[.font:WorkspaceTypography.body(13,weight:.semibold),.foregroundColor:NSColor.white]
        let text=title as NSString,size=text.size(withAttributes:attributes)
        text.draw(at:NSPoint(x:rect.midX-size.width/2,y:rect.midY-size.height/2),withAttributes:attributes)
    }
}

import AppKit

struct AppIconChoice {
    let id:String
    let name:String
    let image:NSImage?
}

/// Icon choices remain visible while a wide app library scrolls horizontally.
final class AppIconSelector:NSView {
    var selected:((String)->Void)?
    private let scroll=NSScrollView(),document=NSView()
    private var buttons:[AppIconButton]=[]
    private var signature=""
    override init(frame:NSRect) {
        super.init(frame:frame)
        scroll.drawsBackground=false;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
        scroll.documentView=document;addSubview(scroll)
        setAccessibilityLabel("App profiles")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    func update(choices:[AppIconChoice],selection:String) {
        let key=selection + "|" + choices.map { $0.id + $0.name }.joined(separator:"|")
        guard key != signature else { return };signature=key
        buttons.forEach { $0.removeFromSuperview() }
        buttons=choices.map { choice in
            let button=AppIconButton(choice:choice,chosen:choice.id == selection)
            button.target=self;button.action=#selector(choose(_:));document.addSubview(button);return button
        }
        needsLayout=true
    }
    override func layout() {
        super.layout();scroll.frame=bounds
        document.frame=NSRect(x:0,y:0,width:max(bounds.width,CGFloat(buttons.count)*108),height:88)
        for (index,button) in buttons.enumerated() { button.frame=NSRect(x:CGFloat(index)*108,y:0,width:100,height:82) }
    }
    @objc private func choose(_ sender:AppIconButton) { selected?(sender.choice.id) }
}

private final class AppIconButton:NSButton {
    let choice:AppIconChoice
    let chosen:Bool
    override var isFlipped:Bool { true }
    init(choice:AppIconChoice,chosen:Bool) {
        self.choice=choice;self.chosen=chosen;super.init(frame:.zero)
        title=choice.name;toolTip=choice.name;isBordered=false;focusRingType = .exterior
        setAccessibilityLabel(choice.name);setAccessibilityValue(chosen ? "Selected":"")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ dirtyRect:NSRect) {
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:12,yRadius:12)
        (chosen ? NSColor.rvAccent.withAlphaComponent(0.10):NSColor.clear).setFill();shape.fill()
        if chosen { NSColor.rvAccent.withAlphaComponent(0.4).setStroke();shape.lineWidth=1;shape.stroke() }
        choice.image?.draw(in:NSRect(x:32,y:10,width:36,height:36),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;paragraph.lineBreakMode = .byTruncatingTail
        (choice.name as NSString).draw(in:NSRect(x:4,y:55,width:92,height:18),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:chosen ? .semibold:.medium),.foregroundColor:chosen ? NSColor.rvAccent:NSColor.rvInk,.paragraphStyle:paragraph])
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds,xRadius:12,yRadius:12).fill() }
    override var focusRingMaskBounds:NSRect { bounds }
}

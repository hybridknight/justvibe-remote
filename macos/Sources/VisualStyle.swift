import AppKit

extension NSColor {
    static let rvBackground = NSColor(srgbRed:0.965,green:0.967,blue:0.98,alpha:1)
    static let rvBorder = NSColor(srgbRed:0.88,green:0.89,blue:0.93,alpha:1)
}

/// Shared surfaces give the workspace and setup guide a consistent palette.
final class WorkspaceSurface: NSView {
    enum Style { case background, sidebar, card, artwork }
    let style:Style
    init(_ style:Style) { self.style=style;super.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    override var isOpaque:Bool { style == .background || style == .sidebar }
    override func draw(_ dirtyRect:NSRect) {
        switch style {
        case .background:
            NSColor.rvBackground.setFill();bounds.fill()
            NSGradient(starting:NSColor.white.withAlphaComponent(0.6),ending:NSColor.rvBackground)?.draw(in:bounds,angle:90)
        case .sidebar:
            NSColor(srgbRed:0.935,green:0.94,blue:0.965,alpha:1).setFill();bounds.fill()
            NSColor.rvBorder.withAlphaComponent(0.7).setFill()
            NSRect(x:bounds.maxX-1,y:0,width:1,height:bounds.height).fill()
        case .card:
            let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:18,yRadius:18)
            NSColor.white.setFill();shape.fill()
            NSColor.rvBorder.withAlphaComponent(0.8).setStroke();shape.lineWidth=1;shape.stroke()
        case .artwork:
            let shape=NSBezierPath(roundedRect:bounds,xRadius:16,yRadius:16)
            NSGradient(starting:NSColor(srgbRed:0.91,green:0.91,blue:0.985,alpha:1),ending:NSColor(srgbRed:0.965,green:0.965,blue:1,alpha:1))?.draw(in:shape,angle:45)
        }
    }
}

final class BrandMark: NSView {
    private static let artwork: NSImage? = Bundle.main.url(forResource:"JustVibeRemote",withExtension:"png").flatMap { NSImage(contentsOf:$0) }
    override func draw(_ dirtyRect:NSRect) {
        let side=min(bounds.width,bounds.height)
        Self.artwork?.draw(in:NSRect(x:bounds.midX-side/2,y:bounds.midY-side/2,width:side,height:side),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    }
}

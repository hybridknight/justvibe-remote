import AppKit
import CoreText

extension NSColor {
    static let rvBackground = NSColor(srgbRed:0.965,green:0.967,blue:0.98,alpha:1)
    static let rvBorder = NSColor(srgbRed:0.88,green:0.89,blue:0.93,alpha:1)
}

/// Fonts are registered only in this process; no system font installation is needed.
enum WorkspaceTypography {
    private static let registration: Void = {
        for name in ["Manrope", "Inter"] {
            if let url=Bundle.main.url(forResource:name,withExtension:"ttf",subdirectory:"Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
            }
        }
    }()
    static func heading(_ size:CGFloat,weight:NSFont.Weight = .semibold)->NSFont {
        font("Manrope",size:size,weight:weight)
    }
    static func body(_ size:CGFloat,weight:NSFont.Weight = .regular)->NSFont {
        font("Inter-Regular",size:size,weight:weight)
    }
    static func text(_ size:CGFloat,weight:NSFont.Weight = .regular)->NSFont {
        size >= 15 ? heading(size,weight:weight):body(size,weight:weight)
    }
    /// Style native controls as well as authored labels; keep aligned device IDs monospaced.
    static func apply(to view:NSView) {
        if let control=view as? NSControl,let current=control.font,
           !["Manrope","Inter"].contains(current.familyName ?? ""),
           !current.fontDescriptor.symbolicTraits.contains(.monoSpace) {
            control.font=body(current.pointSize,weight:current.fontDescriptor.symbolicTraits.contains(.bold) ? .semibold:.regular)
        }
        for child in view.subviews { apply(to:child) }
    }
    private static func font(_ name:String,size:CGFloat,weight:NSFont.Weight)->NSFont {
        _ = registration
        guard let base=NSFont(name:name,size:size) else { return .systemFont(ofSize:size,weight:weight) }
        let value:Double = weight == .bold ? 700 : weight == .semibold ? 600 : weight == .medium ? 500 : 400
        let descriptor=base.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(rawValue:kCTFontVariationAttribute as String): [NSNumber(value:0x77676874):NSNumber(value:value)]
        ])
        return NSFont(descriptor:descriptor,size:size) ?? base
    }
}

/// One spacing scale for page sections, cards, and related controls.
enum WorkspaceSpacing {
    static let tight:CGFloat=4
    static let related:CGFloat=8
    static let controls:CGFloat=12
    static let section:CGFloat=16
    static let page:CGFloat=24
    static let card:CGFloat=24
    static let inset:CGFloat=28
}

/// Keep native search, clear, editing, and keyboard behavior inside a quiet border.
final class WorkspaceSearchField:NSSearchField {
    override init(frame:NSRect) {
        super.init(frame:frame)
        cell=WorkspaceSearchCell(textCell:"")
        isBordered=false;drawsBackground=false;focusRingType = .none
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ dirtyRect:NSRect) {
        let focused=currentEditor() != nil
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10)
        NSColor.white.setFill();shape.fill()
        (focused ? NSColor.rvAccent : NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .secondaryLabelColor:.rvBorder).setStroke()
        shape.lineWidth=focused ? 1.5:1;shape.stroke()
        super.draw(dirtyRect)
    }
    override func becomeFirstResponder()->Bool { let result=super.becomeFirstResponder();needsDisplay=true;return result }
    override func resignFirstResponder()->Bool { let result=super.resignFirstResponder();needsDisplay=true;return result }
    override func textDidBeginEditing(_ notification:Notification) { super.textDidBeginEditing(notification);needsDisplay=true }
    override func textDidEndEditing(_ notification:Notification) { super.textDidEndEditing(notification);needsDisplay=true }
}
private final class WorkspaceSearchCell:NSSearchFieldCell {
    override func searchTextRect(forBounds rect:NSRect)->NSRect {
        var text=super.searchTextRect(forBounds:rect.insetBy(dx:8,dy:1))
        let textFont=font ?? WorkspaceTypography.body(13)
        let height=ceil(textFont.ascender-textFont.descender+textFont.leading)
        text.origin.y=rect.midY-height/2;text.size.height=height
        return text
    }
    override func searchButtonRect(forBounds rect:NSRect)->NSRect { super.searchButtonRect(forBounds:rect.insetBy(dx:8,dy:1)) }
    override func cancelButtonRect(forBounds rect:NSRect)->NSRect { super.cancelButtonRect(forBounds:rect.insetBy(dx:8,dy:1)) }
}

/// Read-only visual export; neither showing nor capturing a view activates its controls.
enum WorkspacePreview {
    static func write(_ view:NSView,to url:URL)throws {
        view.layoutSubtreeIfNeeded()
        let printed=NSImage(data:view.dataWithPDF(inside:view.bounds))
        let cached=view.bitmapImageRepForCachingDisplay(in:view.bounds)
        if let cached { view.cacheDisplay(in:view.bounds,to:cached) }
        let overlay=cached?.cgImage.map { NSImage(cgImage:$0,size:view.bounds.size) }
        let preview=NSImage(size:view.bounds.size,flipped:false) { rect in
            NSColor.white.setFill();rect.fill()
            printed?.draw(in:rect);overlay?.draw(in:rect);return true
        }
        guard let tiff=preview.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),
              let png=bitmap.representation(using:.png,properties:[:]) else {
            throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteUnknownError)
        }
        try png.write(to:url)
    }
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
            NSGradient(colors:[NSColor(srgbRed:0.925,green:0.905,blue:0.975,alpha:1),NSColor(srgbRed:0.975,green:0.973,blue:0.985,alpha:1),NSColor(srgbRed:0.985,green:0.985,blue:0.99,alpha:1)])?.draw(in:bounds,angle:270)
            NSColor.rvBorder.withAlphaComponent(0.45).setFill()
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

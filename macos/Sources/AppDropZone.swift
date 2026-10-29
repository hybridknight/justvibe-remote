import AppKit

/// The app list itself accepts Finder drops without a separate setup panel.
final class AppListDropContainer:NSView {
    var dropped:((URL)->Void)?
    var highlightChanged:((Bool)->Void)?
    private var receiving=false { didSet { needsDisplay=true;if receiving != oldValue { highlightChanged?(receiving) } } }
    override init(frame:NSRect) {
        super.init(frame:frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityLabel("Supported apps. Drop an application from Finder to add it.")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    private func applicationURL(_ pasteboard:NSPasteboard)->URL? {
        guard let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],urls.count == 1,
              (try? LocalAppRegistration(url:urls[0])) != nil else { return nil }
        return urls[0]
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
        receiving=applicationURL(sender.draggingPasteboard) != nil
        if receiving {
            wantsLayer=true;layer?.borderColor=NSColor.rvAccent.withAlphaComponent(0.6).cgColor;layer?.borderWidth=2;layer?.cornerRadius=14
        } else { layer?.borderWidth=0 }
        return receiving ? .copy:[]
    }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation { draggingEntered(sender) }
    private func endDrag() { receiving=false;layer?.borderWidth=0 }
    override func draggingExited(_ sender:NSDraggingInfo?) { endDrag() }
    override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool { applicationURL(sender.draggingPasteboard) != nil }
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        endDrag()
        guard let url=applicationURL(sender.draggingPasteboard) else { return false }
        DispatchQueue.main.async { [weak self] in self?.dropped?(url) }
        return true
    }
    override func concludeDragOperation(_ sender:NSDraggingInfo?) { endDrag() }
}

/// A persistent invitation above the list; the enclosing page handles Finder drops.
final class AppDropPlaceholder:NSButton {
    override var isFlipped:Bool { false }
    var receiving=false { didSet { needsDisplay=true } }
    override init(frame:NSRect) {
        super.init(frame:frame)
        title="";isBordered=false;focusRingType = .exterior
        setAccessibilityLabel("Add app. Drop an application from Finder, or click to choose one.")
        toolTip="Drag an application from Finder, or click to choose an app."
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not used") }
    override func draw(_ dirtyRect:NSRect) {
        let active=receiving || isHighlighted
        let outline=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:16,yRadius:16)
        (NSColor.rvAccent.blended(withFraction:active ? 0.90:0.965,of:.white) ?? .white).setFill();outline.fill()
        NSColor.rvAccent.withAlphaComponent(active ? 0.8:0.3).setStroke()
        outline.lineWidth=active ? 2:1.2
        if !active { outline.setLineDash([6,5],count:2,phase:0) }
        outline.stroke()
        let title=active ? "Drop to add this app":"Drop an app here"
        let subtitle="Drag from Finder, or click to choose an app."
        let titleStyle:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:14,weight:.semibold),.foregroundColor:NSColor.rvAccent]
        let subtitleStyle:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.rvMuted]
        let textWidth=max((title as NSString).size(withAttributes:titleStyle).width,(subtitle as NSString).size(withAttributes:subtitleStyle).width)
        let left=(bounds.width-textWidth-58)/2
        let iconRect=NSRect(x:left,y:(bounds.height-40)/2,width:40,height:40)
        (NSColor.rvAccent.blended(withFraction:active ? 0.86:0.92,of:.white) ?? .white).setFill()
        NSBezierPath(roundedRect:iconRect,xRadius:11,yRadius:11).fill()
        let icon=NSImage(systemSymbolName:"plus.app",accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[.rvAccent]))
        icon?.draw(in:iconRect.insetBy(dx:9,dy:9))
        (title as NSString).draw(at:NSPoint(x:left+58,y:bounds.midY+2),withAttributes:titleStyle)
        (subtitle as NSString).draw(at:NSPoint(x:left+58,y:bounds.midY-20),withAttributes:subtitleStyle)
    }
}

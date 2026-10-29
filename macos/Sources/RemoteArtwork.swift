import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A user-selected visual reference belongs to one remote. Imports are decoded
/// and normalized locally; no paths, metadata, or image URLs enter a plugin.
final class RemoteArtworkStore {
    let url: URL
    private(set) var image: NSImage?
    private(set) var revision=UUID()
    init(directory: URL) {
        url=directory.appendingPathComponent("remote-artwork.png")
        if let data=try? Data(contentsOf:url),data.count <= 8_000_000 { image=NSImage(data:data) }
    }
    func importImage(from source: URL) throws {
        let size=try source.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size>0,size<=20_000_000 else { throw JustVibeRemoteError.message("Choose an image smaller than 20 MB.") }
        let data=try Data(contentsOf:source)
        guard let decoder=CGImageSourceCreateWithData(data as CFData,nil),
              let properties=CGImageSourceCopyPropertiesAtIndex(decoder,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height=properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue>0,height.doubleValue>0,width.doubleValue*height.doubleValue<=80_000_000,
              let thumbnail=CGImageSourceCreateThumbnailAtIndex(decoder,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1024,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {
            throw JustVibeRemoteError.message("This image could not be opened. Try a PNG, JPEG, or HEIC photo.")
        }
        let normalized=NSMutableData()
        guard let encoder=CGImageDestinationCreateWithData(normalized,UTType.png.identifier as CFString,1,nil) else { throw JustVibeRemoteError.message("Could not prepare the remote image.") }
        CGImageDestinationAddImage(encoder,thumbnail,nil)
        guard CGImageDestinationFinalize(encoder),let decoded=NSImage(data:normalized as Data) else { throw JustVibeRemoteError.message("Could not prepare the remote image.") }
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try (normalized as Data).write(to:url,options:.atomic)
        image=decoded;revision=UUID()
    }
    func reset() throws {
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
        image=nil;revision=UUID()
    }
}

/// Shared remote identity: uploaded image, plugin design, then generic fallback.
/// Plugin previews reuse the mapping renderer without enabling interaction.
final class RemoteArtworkView: NSView {
    override var isFlipped: Bool { true }
    private static let designCache:NSCache<NSData,NSImage> = {
        let cache=NSCache<NSData,NSImage>();cache.countLimit=12;cache.totalCostLimit=32_000_000;return cache
    }()
    private var renderedDesign:NSImage?
    var reference: NSImage? { didSet { needsDisplay=true } }
    var remoteLayout: RemoteLayout? {
        didSet {
            guard oldValue != remoteLayout else { return }
            renderedDesign=remoteLayout.flatMap(Self.renderDesign);needsDisplay=true
        }
    }
    override init(frame:NSRect) { super.init(frame:frame);setAccessibilityElement(false) }
    required init?(coder:NSCoder) { super.init(coder:coder);setAccessibilityElement(false) }
    /// Render at design size, then scale the entire result as one image. This
    /// preserves the mapping artwork’s typography and avoids thumbnail controls.
    private static func renderDesign(_ layout:RemoteLayout)->NSImage? {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        guard let data=try? encoder.encode(layout) else { return nil };let key=data as NSData
        if let cached=designCache.object(forKey:key) { return cached }
        let canvas=RemoteCanvas(frame:NSRect(x:0,y:0,width:layout.width+52,height:layout.height+28))
        canvas.update(layout:layout,bindings:[],selection:nil,active:[]);canvas.layoutSubtreeIfNeeded()
        guard let bitmap=canvas.bitmapImageRepForCachingDisplay(in:canvas.bounds) else { return nil }
        canvas.cacheDisplay(in:canvas.bounds,to:bitmap)
        let image=NSImage(size:canvas.bounds.size);image.addRepresentation(bitmap)
        designCache.setObject(image,forKey:key,cost:bitmap.bytesPerRow*bitmap.pixelsHigh);return image
    }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        let uploaded=reference.flatMap { $0.size.width>0 && $0.size.height>0 ? $0:nil }
        if let reference=uploaded ?? renderedDesign {
            let area=bounds.insetBy(dx:10,dy:10)
            let scale=min(area.width/reference.size.width,area.height/reference.size.height)
            let size=NSSize(width:reference.size.width*scale,height:reference.size.height*scale)
            reference.draw(in:NSRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
            return
        }
        let scale=max(0.01,min((bounds.width-24)/112,(bounds.height-24)/330))
        NSGraphicsContext.saveGraphicsState()
        let transform=NSAffineTransform();transform.translateX(by:bounds.midX-56*scale,yBy:bounds.midY-165*scale);transform.scale(by:scale);transform.concat()
        let shell=NSBezierPath(roundedRect:NSRect(x:0,y:0,width:112,height:330),xRadius:25,yRadius:25)
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow();shadow.shadowColor=NSColor.rvInk.withAlphaComponent(0.2);shadow.shadowBlurRadius=12;shadow.shadowOffset=NSSize(width:0,height:7);shadow.set()
        NSColor(white:0.18,alpha:1).setFill();shell.fill();NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors:[NSColor(white:0.32,alpha:1),NSColor(white:0.15,alpha:1),NSColor(white:0.23,alpha:1)])?.draw(in:shell,angle:0)
        NSColor.white.withAlphaComponent(0.22).setStroke();shell.lineWidth=1;shell.stroke()
        let face=NSBezierPath(roundedRect:NSRect(x:4,y:4,width:104,height:322),xRadius:22,yRadius:22)
        NSGradient(starting:NSColor(white:0.18,alpha:1),ending:NSColor(white:0.09,alpha:1))?.draw(in:face,angle:90)
        func key(_ rect:NSRect,accent:Bool=false) {
            let shape=NSBezierPath(roundedRect:rect,xRadius:min(rect.width,rect.height)/2,yRadius:min(rect.width,rect.height)/2)
            NSGradient(starting:accent ? NSColor(srgbRed:0.48,green:0.47,blue:1,alpha:1):NSColor(white:0.29,alpha:1),ending:accent ? .rvAccent:NSColor(white:0.18,alpha:1))?.draw(in:shape,angle:90)
            NSColor.white.withAlphaComponent(0.08).setStroke();shape.lineWidth=0.8;shape.stroke()
        }
        func symbol(_ name:String,in rect:NSRect,tint:NSColor = .white) {
            guard let icon=NSImage(systemSymbolName:name,accessibilityDescription:nil) else { return }
            let tinted=NSImage(size:icon.size,flipped:false) { target in
                icon.draw(in:target);tint.set();target.fill(using:.sourceAtop);return true
            }
            tinted.draw(in:rect,from:.zero,operation:.sourceOver,fraction:0.9,respectFlipped:true,hints:nil)
        }
        key(NSRect(x:17,y:22,width:23,height:23));symbol("power",in:NSRect(x:23,y:28,width:11,height:11),tint:NSColor(srgbRed:1,green:0.5,blue:0.5,alpha:1))
        key(NSRect(x:72,y:22,width:23,height:23));symbol("ellipsis",in:NSRect(x:78,y:28,width:11,height:11))
        let ring=NSBezierPath(ovalIn:NSRect(x:17,y:65,width:78,height:78))
        NSGradient(starting:NSColor(white:0.28,alpha:1),ending:NSColor(white:0.16,alpha:1))?.draw(in:ring,angle:90)
        NSColor.black.withAlphaComponent(0.3).setStroke();ring.lineWidth=1;ring.stroke()
        key(NSRect(x:39,y:87,width:34,height:34));symbol("circle.fill",in:NSRect(x:53,y:101,width:6,height:6))
        for (name,x,y) in [("chevron.up",51.0,73.0),("chevron.down",51.0,126.0),("chevron.left",25.0,100.0),("chevron.right",78.0,100.0)] { symbol(name,in:NSRect(x:x,y:y,width:9,height:9),tint:NSColor(white:0.8,alpha:1)) }
        key(NSRect(x:17,y:163,width:23,height:23));symbol("arrow.uturn.backward",in:NSRect(x:23,y:169,width:11,height:11))
        key(NSRect(x:72,y:163,width:23,height:23));symbol("house",in:NSRect(x:78,y:169,width:11,height:11))
        key(NSRect(x:39,y:192,width:34,height:34),accent:true);symbol("mic.fill",in:NSRect(x:50,y:201,width:12,height:16))
        key(NSRect(x:20,y:241,width:26,height:48));symbol("plus",in:NSRect(x:29,y:250,width:8,height:8));symbol("minus",in:NSRect(x:29,y:273,width:8,height:8))
        key(NSRect(x:66,y:241,width:26,height:48));symbol("chevron.up",in:NSRect(x:75,y:250,width:8,height:8));symbol("chevron.down",in:NSRect(x:75,y:273,width:8,height:8))
        NSColor.white.withAlphaComponent(0.2).setFill()
        for x in [51.0,56.0,61.0] { NSBezierPath(ovalIn:NSRect(x:x,y:310,width:2,height:2)).fill() }
        NSGraphicsContext.restoreGraphicsState()
    }
}

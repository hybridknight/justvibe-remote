import AppKit

private final class CursorDocument:NSView { override var isFlipped:Bool { true } }
final class CursorSetup:NSObject,NSWindowDelegate {
    private let controller:RemoteController
    private weak var parent:NSWindow?
    private let panel:NSPanel
    private let scroll=NSScrollView(),document=CursorDocument()
    private let stack=NSStackView()
    private let status=NSTextField(wrappingLabelWithString:"")
    private let linear=NSButton(checkboxWithTitle:"Turn off native macOS acceleration for this remote",target:nil,action:nil)
    private let slider=NSSlider(value:0.6875,minValue:0,maxValue:3,target:nil,action:nil)
    private let level=NSTextField(labelWithString:"")
    private var nativeButtons:[NSButton]=[]
    private var ended=false
    var finished:(()->Void)?
    init(controller:RemoteController,parent:NSWindow) {
        self.controller=controller;self.parent=parent
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:720,height:min(520,max(600,(parent.screen ?? NSScreen.main)?.visibleFrame.height ?? 920)-100)),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init();panel.title="Remote cursor settings";panel.delegate=self;panel.isReleasedWhenClosed=false;panel.appearance=NSAppearance(named:.aqua)
        let root=NSView();root.wantsLayer=true;root.layer?.backgroundColor=NSColor.white.cgColor;panel.contentView=root
        scroll.frame=root.bounds;scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true;scroll.drawsBackground=false;root.addSubview(scroll)
        document.frame=NSRect(x:0,y:0,width:root.bounds.width,height:800);document.autoresizingMask=[.width];scroll.documentView=document
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:26)])
        func label(_ text:String,size:CGFloat=13,bold:Bool=false)->NSTextField { let f=NSTextField(wrappingLabelWithString:text);f.font = .systemFont(ofSize:size,weight:bold ? .bold:.regular);f.textColor = .rvInk;return f }
        func button(_ title:String,_ action:Selector)->NSButton { NSButton(title:title,target:self,action:action) }
        stack.addArrangedSubview(label("Remote cursor settings",size:24,bold:true))
        stack.addArrangedSubview(label("Adjust cursor speed and acceleration for \(controller.config.profile.name). Other mice and your trackpad keep their settings."))
        let separator=NSBox();separator.boxType = .separator;separator.widthAnchor.constraint(equalToConstant:640).isActive=true;stack.addArrangedSubview(separator)
        stack.addArrangedSubview(label("Native tracking speed",size:16,bold:true))
        stack.addArrangedSubview(label("With acceleration off, the remote uses its native movement rate. Turn acceleration on to adjust the tracking-speed slider.",size:12))
        linear.target=self;linear.action=#selector(slide);linear.state = .on;stack.addArrangedSubview(linear)
        slider.target=self;slider.action=#selector(slide);slider.widthAnchor.constraint(equalToConstant:640).isActive=true;slider.setAccessibilityLabel("Native remote cursor tracking speed");stack.addArrangedSubview(slider);stack.addArrangedSubview(level)
        nativeButtons=[button("Try native settings",#selector(preview)),button("Save native settings",#selector(saveNative)),button("Reset native speed",#selector(resetNative))]
        stack.addArrangedSubview(NSStackView(views:nativeButtons))
        status.font = .systemFont(ofSize:12);status.textColor = .rvMuted;stack.addArrangedSubview(status)
        stack.addArrangedSubview(NSStackView(views:[button("Close",#selector(close))]))
        do { let native=try controller.currentCursorSpeed();slider.doubleValue=native<0 ? controller.config.cursorSettings[controller.config.devicePluginID]?.level ?? 0.6875 : native;linear.state=(controller.config.cursorSettings[controller.config.devicePluginID]?.linear ?? (native<0)) ? .on:.off } catch { status.stringValue=error.localizedDescription }
        refresh();scroll.contentView.scroll(to:.zero)
    }
    private func fitDocument() { document.layoutSubtreeIfNeeded();document.setFrameSize(NSSize(width:document.frame.width,height:max(scroll.contentSize.height,stack.fittingSize.height+52))) }
    private func refresh() {
        slide();fitDocument()
    }
    func show() { controller.beginCursorSettings();parent?.beginSheet(panel) }
    private var setting:CursorSpeedSettings { CursorSpeedSettings(level:slider.doubleValue,linear:linear.state == .on) }
    @objc private func slide() {
        slider.isEnabled=linear.state != .on
        level.stringValue=linear.state == .on ? "Acceleration off · native movement rate" : "Tracking speed: \(Int((slider.doubleValue/3*100).rounded())) / 100"
    }
    @objc private func preview() { do { try controller.previewCursorSpeed(setting);status.stringValue="Native settings preview active. Closing discards unsaved native changes." } catch { status.stringValue=error.localizedDescription };fitDocument() }
    @objc private func saveNative() { do { try controller.saveCursorSpeed(setting);status.stringValue="Native tracking speed saved for this remote." } catch { status.stringValue=error.localizedDescription };fitDocument() }
    @objc private func resetNative() { do { try controller.resetCursorSpeed();let value=try controller.currentCursorSpeed();slider.doubleValue=value<0 ? 0.6875:value;linear.state=value<0 ? .on:.off;status.stringValue="Original native speed restored.";refresh() } catch { status.stringValue=error.localizedDescription };fitDocument() }
    @objc private func close() {
        guard !ended else{return}
        do { try controller.endCursorSettings() } catch { status.stringValue=error.localizedDescription;return }
        ended=true;parent?.endSheet(panel);panel.orderOut(nil);finished?()
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { close();return false }
    func render(to url:URL)throws {
        guard let view=panel.contentView else{return};view.layoutSubtreeIfNeeded()
        if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) { view.cacheDisplay(in:view.bounds,to:bitmap);if let png=bitmap.representation(using:.png,properties:[:]) { try png.write(to:url) } }
    }
}

import AppKit

/// Pair or connect first, then identify the remote and hand off missing support.
final class AddRemoteFlow:NSObject,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
    private let parent:NSWindow
    private let catalog:PluginCatalog
    private let panel:NSPanel
    private let table=NSTableView(),detail=NSTextField(wrappingLabelWithString:"")
    private let titleLabel=NSTextField(labelWithString:""),subtitle=NSTextField(wrappingLabelWithString:""),stepLabel=NSTextField(labelWithString:"")
    private let feedback=NSTextField(labelWithString:"")
    private let receiverPage=NSView(),agentPage=NSView(),promptText=NSTextView()
    private var primary:NSButton!,back:NSButton!
    private var devices:[DiscoveredRemote]=[]
    private var manual=false,ended=false,showingPrompt=false
    var openRemote:((String)->Void)?
    var managePlugins:(()->Void)?
    var finished:(()->Void)?

    init(parent:NSWindow,catalog:PluginCatalog) {
        self.parent=parent;self.catalog=catalog
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:880,height:660),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        super.init();panel.title="Add a remote";panel.isReleasedWhenClosed=false;panel.delegate=self
        panel.appearance=NSAppearance(named:.aqua);panel.minSize=NSSize(width:840,height:620)
        build();rescan();if let root=panel.contentView { WorkspaceTypography.apply(to:root) }
    }
    private func label(_ title:String,size:CGFloat=13,weight:NSFont.Weight = .regular,muted:Bool=false)->NSTextField {
        let text=NSTextField(wrappingLabelWithString:title);text.font = WorkspaceTypography.text(size,weight:weight);text.textColor=muted ? .rvMuted:.rvInk
        text.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);return text
    }
    private func button(_ title:String,_ action:Selector)->NSButton {
        let button=NSButton(title:title,target:self,action:action);button.bezelStyle = .rounded;button.controlSize = .large;return button
    }
    private func pin(_ child:NSView,to parent:NSView,inset:CGFloat=0) {
        parent.addSubview(child);child.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo:parent.leadingAnchor,constant:inset),child.trailingAnchor.constraint(equalTo:parent.trailingAnchor,constant:-inset),child.topAnchor.constraint(equalTo:parent.topAnchor,constant:inset),child.bottomAnchor.constraint(equalTo:parent.bottomAnchor,constant:-inset)])
    }
    private func build() {
        let root=WorkspaceSurface(.background);panel.contentView=root
        let header=NSStackView();header.orientation = .vertical;header.alignment = .leading;header.spacing=WorkspaceSpacing.related
        stepLabel.font = WorkspaceTypography.body(10,weight:.semibold);stepLabel.textColor = .rvAccent
        titleLabel.font = WorkspaceTypography.heading(26,weight:.bold);titleLabel.textColor = .rvInk
        subtitle.font = WorkspaceTypography.body(13);subtitle.textColor = .rvMuted
        [stepLabel,titleLabel,subtitle].forEach { header.addArrangedSubview($0) }
        root.addSubview(header);header.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:WorkspaceSpacing.inset),header.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-WorkspaceSpacing.inset),header.topAnchor.constraint(equalTo:root.topAnchor,constant:24),header.heightAnchor.constraint(equalToConstant:104)])
        let divider=NSBox();divider.boxType = .separator;root.addSubview(divider);divider.translatesAutoresizingMaskIntoConstraints=false
        primary=PrimaryButton(title:"Continue",target:self,action:#selector(proceed));primary.isBordered=false;primary.keyEquivalent="\r"
        back=button("Cancel",#selector(goBack));back.keyEquivalent="\u{1b}"
        feedback.font = WorkspaceTypography.body(11);feedback.textColor = .rvMuted;feedback.lineBreakMode = .byTruncatingTail
        let footer=NSStackView(views:[back,feedback,primary]);footer.spacing=WorkspaceSpacing.section
        feedback.setContentHuggingPriority(.init(1),for:.horizontal)
        root.addSubview(footer);footer.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:WorkspaceSpacing.inset),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-WorkspaceSpacing.inset),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20),footer.heightAnchor.constraint(equalToConstant:38),divider.leadingAnchor.constraint(equalTo:root.leadingAnchor),divider.trailingAnchor.constraint(equalTo:root.trailingAnchor),divider.bottomAnchor.constraint(equalTo:footer.topAnchor,constant:-16)])
        let host=NSView();root.addSubview(host);host.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:WorkspaceSpacing.inset),host.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-WorkspaceSpacing.inset),host.topAnchor.constraint(equalTo:header.bottomAnchor,constant:8),host.bottomAnchor.constraint(equalTo:divider.topAnchor,constant:-20)])
        pin(receiverPage,to:host);pin(agentPage,to:host)
        buildReceiverPage();buildAgentPage()
    }
    private func buildReceiverPage() {
        let connection=label("Bluetooth remote? Pair it in macOS System Settings → Bluetooth first and make sure it is connected. Then click Refresh below. For a USB remote, plug in its receiver.",size:12,muted:true)
        receiverPage.addSubview(connection);connection.translatesAutoresizingMaskIntoConstraints=false
        let heading=NSStackView(views:[label("Connected devices",size:13,weight:.semibold),NSView(),button("Refresh",#selector(rescan))]);heading.spacing=WorkspaceSpacing.controls
        receiverPage.addSubview(heading);heading.translatesAutoresizingMaskIntoConstraints=false
        let card=WorkspaceSurface(.card);receiverPage.addSubview(card);card.translatesAutoresizingMaskIntoConstraints=false
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        for (id,width) in [("device",520.0),("support",220.0)] { let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));column.width=width;table.addTableColumn(column) }
        table.headerView=nil;table.delegate=self;table.dataSource=self;table.rowHeight=80;table.intercellSpacing=NSSize(width:0,height:4)
        table.style = .inset;table.backgroundColor = .white;table.allowsEmptySelection=true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle;table.setAccessibilityLabel("Connected USB and Bluetooth input devices")
        scroll.documentView=table;pin(scroll,to:card,inset:8)
        let hint=label("Not sure which one? Turn the remote off and on, or reconnect its USB receiver, then refresh.",size:11,muted:true)
        receiverPage.addSubview(hint);hint.translatesAutoresizingMaskIntoConstraints=false
        detail.font = WorkspaceTypography.body(12);detail.textColor = .rvMuted
        receiverPage.addSubview(detail);detail.translatesAutoresizingMaskIntoConstraints=false
        let missing=button("Get an agent setup prompt…",#selector(notListed))
        missing.toolTip="After pairing or connecting, let your agent identify the remote and help finish setup."
        receiverPage.addSubview(missing);missing.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            connection.leadingAnchor.constraint(equalTo:receiverPage.leadingAnchor),connection.trailingAnchor.constraint(equalTo:receiverPage.trailingAnchor),connection.topAnchor.constraint(equalTo:receiverPage.topAnchor),connection.heightAnchor.constraint(equalToConstant:44),
            heading.leadingAnchor.constraint(equalTo:receiverPage.leadingAnchor),heading.trailingAnchor.constraint(equalTo:receiverPage.trailingAnchor),heading.topAnchor.constraint(equalTo:connection.bottomAnchor,constant:8),heading.heightAnchor.constraint(equalToConstant:30),
            card.leadingAnchor.constraint(equalTo:receiverPage.leadingAnchor),card.trailingAnchor.constraint(equalTo:receiverPage.trailingAnchor),card.topAnchor.constraint(equalTo:heading.bottomAnchor,constant:10),card.bottomAnchor.constraint(equalTo:hint.topAnchor,constant:-12),
            hint.leadingAnchor.constraint(equalTo:receiverPage.leadingAnchor),hint.trailingAnchor.constraint(equalTo:receiverPage.trailingAnchor),hint.bottomAnchor.constraint(equalTo:detail.topAnchor,constant:-8),hint.heightAnchor.constraint(equalToConstant:18),
            detail.leadingAnchor.constraint(equalTo:receiverPage.leadingAnchor),detail.trailingAnchor.constraint(equalTo:receiverPage.trailingAnchor),detail.bottomAnchor.constraint(equalTo:missing.topAnchor,constant:-8),detail.heightAnchor.constraint(equalToConstant:34),
            missing.leadingAnchor.constraint(equalTo:receiverPage.leadingAnchor),missing.bottomAnchor.constraint(equalTo:receiverPage.bottomAnchor),missing.heightAnchor.constraint(equalToConstant:36)
        ])
    }
    private func buildAgentPage() {
        let guideCard=WorkspaceSurface(.card),promptCard=WorkspaceSurface(.card)
        for view in [guideCard,promptCard] { agentPage.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([guideCard.leadingAnchor.constraint(equalTo:agentPage.leadingAnchor),guideCard.topAnchor.constraint(equalTo:agentPage.topAnchor),guideCard.bottomAnchor.constraint(equalTo:agentPage.bottomAnchor),guideCard.widthAnchor.constraint(equalToConstant:228),promptCard.leadingAnchor.constraint(equalTo:guideCard.trailingAnchor,constant:16),promptCard.trailingAnchor.constraint(equalTo:agentPage.trailingAnchor),promptCard.topAnchor.constraint(equalTo:agentPage.topAnchor),promptCard.bottomAnchor.constraint(equalTo:agentPage.bottomAnchor)])
        let guide=NSStackView();guide.orientation = .vertical;guide.alignment = .leading;guide.spacing=WorkspaceSpacing.section
        guideCard.addSubview(guide);guide.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([guide.leadingAnchor.constraint(equalTo:guideCard.leadingAnchor,constant:18),guide.trailingAnchor.constraint(equalTo:guideCard.trailingAnchor,constant:-18),guide.topAnchor.constraint(equalTo:guideCard.topAnchor,constant:20),guide.bottomAnchor.constraint(lessThanOrEqualTo:guideCard.bottomAnchor,constant:-16)])
        guide.addArrangedSubview(label("Get help from an agent",size:14,weight:.semibold))
        func step(_ number:String,_ title:String,_ text:String) {
            let content=NSStackView();content.orientation = .vertical;content.alignment = .leading;content.spacing=WorkspaceSpacing.related
            content.addArrangedSubview(label(number + "  " + title,size:12,weight:.semibold))
            content.addArrangedSubview(label(text,size:11,muted:true));guide.addArrangedSubview(content)
            content.widthAnchor.constraint(equalTo:guide.widthAnchor).isActive=true
            for child in content.arrangedSubviews { child.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true }
        }
        step("01","Pair or connect first","Bluetooth: pair in System Settings → Bluetooth and keep the remote connected. USB: plug in its receiver.")
        step("02","Copy into your agent","Paste the prompt into your coding agent and attach a clear front photo or the remote’s brand and model.")
        let starter=button("Show starter files…",#selector(showStarter));starter.controlSize = .small
        starter.toolTip="Share these starter files if your agent can’t read local folders.";guide.addArrangedSubview(starter)
        step("03","Let the agent finish setup","The agent checks existing support, creates and validates a plugin if needed, and helps you install and test it.")
        let install=button("Manage plugins…",#selector(plugins));install.controlSize = .small;guide.addArrangedSubview(install)
        let promptTitle=label("Setup prompt",size:13,weight:.semibold)
        promptCard.addSubview(promptTitle);promptTitle.translatesAutoresizingMaskIntoConstraints=false
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        promptText.isEditable=false;promptText.isSelectable=true;promptText.isRichText=false;promptText.font = WorkspaceTypography.body(12)
        promptText.textColor = .rvInk;promptText.backgroundColor = .white;promptText.textContainerInset=NSSize(width:8,height:8)
        promptText.frame=NSRect(x:0,y:0,width:500,height:320);promptText.minSize=NSSize(width:0,height:0);promptText.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        promptText.isVerticallyResizable=true;promptText.isHorizontallyResizable=false;promptText.autoresizingMask = [.width]
        promptText.textContainer?.widthTracksTextView=true;promptText.textContainer?.containerSize=NSSize(width:500,height:CGFloat.greatestFiniteMagnitude)
        promptText.setAccessibilityLabel("Full setup prompt. Select text or use Copy prompt.")
        scroll.documentView=promptText;promptCard.addSubview(scroll);scroll.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([promptTitle.leadingAnchor.constraint(equalTo:promptCard.leadingAnchor,constant:18),promptTitle.topAnchor.constraint(equalTo:promptCard.topAnchor,constant:16),scroll.leadingAnchor.constraint(equalTo:promptCard.leadingAnchor,constant:10),scroll.trailingAnchor.constraint(equalTo:promptCard.trailingAnchor,constant:-10),scroll.topAnchor.constraint(equalTo:promptTitle.bottomAnchor,constant:10),scroll.bottomAnchor.constraint(equalTo:promptCard.bottomAnchor,constant:-12)])
    }
    func show() { parent.beginSheet(panel) }
    func render(to url:URL,showPrompt:Bool=false,compact:Bool=false) throws {
        if compact { panel.setContentSize(NSSize(width:840,height:620)) }
        if showPrompt { manual=true;showingPrompt=true;updateSelection() }
        guard let root=panel.contentView else { return }
        try WorkspacePreview.write(root,to:url)
    }
    @objc private func rescan() {
        let selection=selectedDevice?.id
        devices=RemoteDiscovery.scan().sorted { a,b in
            let aSupported = !a.matchingPlugins(in:catalog).isEmpty,bSupported = !b.matchingPlugins(in:catalog).isEmpty
            if aSupported != bSupported { return aSupported }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        table.reloadData();table.deselectAll(nil);manual=devices.isEmpty;feedback.stringValue=""
        if let row=devices.firstIndex(where:{$0.id == selection}) { table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false) }
        updateSelection()
    }
    private var selectedDevice:DiscoveredRemote? { devices.indices.contains(table.selectedRow) ? devices[table.selectedRow]:nil }
    func numberOfRows(in tableView:NSTableView)->Int { devices.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let device=devices[row],matches=device.matchingPlugins(in:catalog)
        if tableColumn?.identifier.rawValue == "support" {
            let cell=ReceiverDeviceCell(),text=NSTextField(labelWithString:matches.count == 1 ? "Ready to set up":matches.isEmpty ? "Create plugin":"Review plugins")
            text.font = WorkspaceTypography.body(11,weight:.medium);text.textColor = .rvInk
            cell.textField=text;cell.addSubview(text);text.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),text.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            cell.updateContrast();return cell
        }
        let cell=ReceiverDeviceCell(),name=NSTextField(labelWithString:device.name),info=NSTextField(labelWithString:device.transport + " · " + device.hardwareID),manufacturer=NSTextField(labelWithString:"Manufacturer: " + (device.manufacturer ?? "Not reported")),icon=NSImageView()
        icon.image=NSImage(systemSymbolName:device.transport.lowercased().contains("bluetooth") ? "wave.3.right":"cable.connector",accessibilityDescription:nil);icon.contentTintColor = .rvMuted
        name.font = WorkspaceTypography.body(13,weight:.medium);name.lineBreakMode = .byTruncatingTail
        info.font = .monospacedSystemFont(ofSize:10,weight:.regular);info.textColor = .rvMuted
        manufacturer.font = WorkspaceTypography.body(11);manufacturer.lineBreakMode = .byTruncatingTail
        manufacturer.toolTip=manufacturer.stringValue
        info.lineBreakMode = .byTruncatingTail
        cell.textField=name;cell.imageView=icon
        for view in [icon,name,manufacturer,info] { cell.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),icon.widthAnchor.constraint(equalToConstant:24),icon.heightAnchor.constraint(equalToConstant:24),icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),name.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:12),name.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),name.centerYAnchor.constraint(equalTo:cell.centerYAnchor,constant:-20),manufacturer.leadingAnchor.constraint(equalTo:name.leadingAnchor),manufacturer.trailingAnchor.constraint(equalTo:name.trailingAnchor),manufacturer.topAnchor.constraint(equalTo:name.bottomAnchor,constant:3),info.leadingAnchor.constraint(equalTo:name.leadingAnchor),info.trailingAnchor.constraint(equalTo:name.trailingAnchor),info.topAnchor.constraint(equalTo:manufacturer.bottomAnchor,constant:3)])
        cell.updateContrast();return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification) { manual=false;feedback.stringValue="";updateSelection() }
    private var authoringResources:URL { Bundle.main.resourceURL!.appendingPathComponent("PluginAuthoring") }
    private func updateSelection() {
        receiverPage.isHidden=showingPrompt;agentPage.isHidden = !showingPrompt
        stepLabel.stringValue=showingPrompt ? (selectedDevice == nil ? "STEP 2 OF 2  ·  FIND YOUR REMOTE":"STEP 2 OF 2  ·  CREATE SUPPORT"):"STEP 1 OF 2  ·  CONNECT YOUR REMOTE"
        titleLabel.stringValue=showingPrompt ? (selectedDevice == nil ? "Help me find my remote":"Create a remote plugin"):"Add your remote"
        subtitle.stringValue=showingPrompt ? selectedDevice.map { "Create support for \($0.name) with your coding agent." } ?? "Copy this prompt after pairing or connecting. Your agent will guide the rest." : "Pair or connect first. Then select your remote or get an agent setup prompt."
        back.title=showingPrompt ? "Back":"Cancel"
        if showingPrompt {
            let text=RemoteSetupPrompt.make(device:selectedDevice)
            if text != promptText.string {
                promptText.string=text
                let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=3;paragraph.paragraphSpacing=7
                promptText.textStorage?.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:(text as NSString).length))
                promptText.sizeToFit();promptText.scrollToBeginningOfDocument(nil)
            }
            primary.title="Copy prompt";primary.isEnabled=true;return
        }
        primary.isEnabled=selectedDevice != nil || manual
        guard let device=selectedDevice else {
            detail.stringValue=devices.isEmpty ? "No connected input devices found. Pair or connect first, then Refresh. Still missing? Get an agent setup prompt.":"Select your remote. Other keyboards and mice may also appear. Unsure? Get an agent setup prompt."
            primary.title="Continue";return
        }
        let matches=device.matchingPlugins(in:catalog)
        detail.stringValue=matches.count == 1 ? "\(matches[0].name) is already supported. Open it to finish setup.":matches.isEmpty ? "This device needs a plugin. Next, we’ll prepare a prompt with its detected details.":"Multiple plugins match this device. Review them before connecting."
        primary.title=matches.count == 1 ? "Open remote":matches.isEmpty ? "Create plugin":"Review plugins"
    }
    @objc private func notListed() { table.deselectAll(nil);manual=true;showingPrompt=true;feedback.stringValue="";updateSelection() }
    @objc private func goBack() {
        if showingPrompt { showingPrompt=false;feedback.stringValue="";updateSelection() }
        else { close() }
    }
    @objc private func proceed() {
        if showingPrompt { copyPrompt();return }
        guard selectedDevice != nil || manual else { return }
        if let device=selectedDevice {
            let matches=device.matchingPlugins(in:catalog)
            if matches.count == 1 { let id=matches[0].id;close();openRemote?(id);return }
            if matches.count > 1 { plugins();return }
        }
        showingPrompt=true;feedback.stringValue="";updateSelection()
    }
    @objc private func showStarter() { NSWorkspace.shared.activateFileViewerSelecting([authoringResources.appendingPathComponent("device")]) }
    private func copyPrompt() {
        guard showingPrompt,!promptText.string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(promptText.string,forType:.string) else { feedback.stringValue="Couldn’t copy. Please try again.";return }
        feedback.stringValue="Copied. Paste into your agent and upload a remote photo."
        primary.title="Copy again"
    }
    @objc private func plugins() { close();managePlugins?() }
    @objc private func close() { guard !ended else{return};ended=true;parent.endSheet(panel);panel.orderOut(nil);finished?() }
    func windowShouldClose(_ sender:NSWindow)->Bool { close();return false }
}

/// AppKit changes backgroundStyle as rows gain or lose selection, including keyboard focus.
private final class ReceiverDeviceCell:NSTableCellView {
    override var backgroundStyle:NSView.BackgroundStyle { didSet { updateContrast() } }
    func updateContrast() {
        let selected=backgroundStyle == .emphasized
        for text in subviews.compactMap({ $0 as? NSTextField }) {
            text.textColor=selected ? .white : (text === textField ? .rvInk:.rvMuted)
        }
        imageView?.contentTintColor=selected ? .white:.rvMuted
    }
}

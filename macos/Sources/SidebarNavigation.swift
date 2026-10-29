import AppKit

/// Native source-list navigation gives selection, focus, and keyboard traversal
/// the same behavior as other Mac sidebars.
final class SidebarNavigation: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private struct Entry {
        let title: String
        let page: WorkspacePage?
    }
    private let table=NSTableView()
    private var entries:[Entry]=[]
    private var remoteName:String?
    private var updating=false
    var selected:((WorkspacePage)->Void)?
    var hasKeyboardFocus: Bool {
        guard let responder=window?.firstResponder as? NSView else { return false }
        return responder === table || responder.isDescendant(of:self)
    }

    override init(frame:NSRect) {
        super.init(frame:frame)
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("navigation"))
        table.addTableColumn(column);table.headerView=nil
        table.style = .sourceList;table.rowSizeStyle = .medium;table.rowHeight=38
        table.intercellSpacing=NSSize(width:0,height:4)
        table.backgroundColor = .clear;table.focusRingType = .default
        table.allowsMultipleSelection=false;table.allowsEmptySelection=false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource=self;table.delegate=self
        table.setAccessibilityLabel("Sidebar navigation")
        let scroll=NSScrollView();scroll.drawsBackground=false;scroll.hasVerticalScroller=true
        scroll.autohidesScrollers=true;scroll.documentView=table
        addSubview(scroll);scroll.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:leadingAnchor),scroll.trailingAnchor.constraint(equalTo:trailingAnchor),scroll.topAnchor.constraint(equalTo:topAnchor),scroll.bottomAnchor.constraint(equalTo:bottomAnchor)])
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(page:WorkspacePage,remoteName:String?) {
        updating=true;defer { updating=false }
        if entries.isEmpty || self.remoteName != remoteName {
            self.remoteName=remoteName
            entries=[Entry(title:"Library",page:nil),Entry(title:WorkspacePage.remotes.title,page:.remotes),Entry(title:WorkspacePage.plugins.title,page:.plugins)]
            if let remoteName {
                entries.append(Entry(title:remoteName,page:nil))
                entries += WorkspacePage.allCases.filter(\.isRemoteScoped).map { Entry(title:$0.sidebarTitle,page:$0) }
            }
            entries += [Entry(title:"Resources",page:nil),Entry(title:WorkspacePage.help.title,page:.help)]
            table.reloadData()
        }
        if let row=entries.firstIndex(where: { $0.page == page }),table.selectedRow != row {
            table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        }
    }
    func numberOfRows(in tableView:NSTableView)->Int { entries.count }
    func tableView(_ tableView:NSTableView,isGroupRow row:Int)->Bool { entries[row].page == nil }
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int)->Bool { entries[row].page != nil }
    func tableView(_ tableView:NSTableView,heightOfRow row:Int)->CGFloat { entries[row].page == nil ? 34:38 }
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView? { SidebarRow() }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let entry=entries[row]
        let cell=NSTableCellView();cell.toolTip=entry.title
        let title=NSTextField(labelWithString:entry.title);title.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize:entry.page == nil ? 11:13,weight:entry.page == nil ? .semibold:.medium)
        title.textColor=entry.page == nil ? .secondaryLabelColor:.labelColor
        cell.textField=title;cell.addSubview(title);title.translatesAutoresizingMaskIntoConstraints=false
        if let page=entry.page {
            let icon=NSImageView()
            icon.image=NSImage(systemSymbolName:page.symbol,accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:15,weight:.regular))
            icon.contentTintColor = .secondaryLabelColor;icon.imageScaling = .scaleProportionallyDown
            cell.imageView=icon;cell.addSubview(icon);icon.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:10),icon.widthAnchor.constraint(equalToConstant:20),icon.heightAnchor.constraint(equalToConstant:20),icon.centerYAnchor.constraint(equalTo:cell.centerYAnchor),title.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:9)])
        } else { title.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:10).isActive=true }
        NSLayoutConstraint.activate([title.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-10),title.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification) {
        guard !updating,entries.indices.contains(table.selectedRow),let page=entries[table.selectedRow].page else { return }
        selected?(page)
    }
}

private final class SidebarRow:NSTableRowView {
    override var interiorBackgroundStyle:NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect:NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect=bounds.insetBy(dx:3,dy:1)
        NSColor.rvAccent.withAlphaComponent(0.11).setFill()
        NSBezierPath(roundedRect:rect,xRadius:9,yRadius:9).fill()
        NSColor.rvAccent.setFill()
        NSBezierPath(roundedRect:NSRect(x:rect.minX,y:rect.midY-8,width:3,height:16),xRadius:1.5,yRadius:1.5).fill()
    }
}

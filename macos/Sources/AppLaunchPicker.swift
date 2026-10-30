import AppKit

/// Keeps checkbox state and per-app locations attached to app identity while rows move.
final class AppLaunchPicker: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private struct Entry {
        var app: LaunchApp
        var name: String
        var checked: Bool
    }
    private var entries: [Entry]
    private let table=NSTableView()
    private let dragType=NSPasteboard.PasteboardType("org.justviberemote.launch-app-row")
    var selectedApps: [LaunchApp] { entries.filter(\.checked).map(\.app) }

    init(apps:[PluginManifest],saved:[LaunchApp]) {
        let ordered=saved.compactMap { item in apps.first(where:{$0.id == item.id}) } + apps.filter { app in !saved.contains(where:{$0.id == app.id}) }
        entries=ordered.map { app in Entry(app:saved.first(where:{$0.id == app.id}) ?? LaunchApp(id:app.id),name:app.name,checked:saved.contains(where:{$0.id == app.id})) }
        super.init(frame:NSRect(x:0,y:0,width:360,height:min(300,CGFloat(entries.count*32+8))+38))
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("app"))
        table.addTableColumn(column);table.headerView=nil;table.rowHeight=30
        table.style = .plain;table.intercellSpacing=NSSize(width:0,height:2)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsMultipleSelection=false;table.dataSource=self;table.delegate=self
        table.setAccessibilityLabel("Apps in opening order. Drag rows to reorder, or select a row and use Move up or Move down.")
        table.registerForDraggedTypes([dragType])
        table.setDraggingSourceOperationMask(.move,forLocal:true)
        table.setDraggingSourceOperationMask([],forLocal:false)
        table.reloadData()
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.documentView=table
        let up=NSButton(title:"Move up",target:self,action:#selector(moveSelectedUp))
        let down=NSButton(title:"Move down",target:self,action:#selector(moveSelectedDown))
        up.bezelStyle = .rounded;down.bezelStyle = .rounded
        let controls=NSStackView(views:[up,down]);controls.spacing=8
        addSubview(scroll);addSubview(controls)
        scroll.translatesAutoresizingMaskIntoConstraints=false;controls.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:leadingAnchor),scroll.trailingAnchor.constraint(equalTo:trailingAnchor),scroll.topAnchor.constraint(equalTo:topAnchor),
            controls.topAnchor.constraint(equalTo:scroll.bottomAnchor,constant:8),controls.leadingAnchor.constraint(equalTo:leadingAnchor),controls.bottomAnchor.constraint(equalTo:bottomAnchor)
        ])
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func numberOfRows(in tableView:NSTableView)->Int { entries.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let check=NSButton(checkboxWithTitle:"",target:self,action:#selector(toggleApp(_:)))
        check.tag=row;check.state=entries[row].checked ? .on:.off;check.setAccessibilityLabel(entries[row].name)
        let name=NSTextField(labelWithString:entries[row].name);name.lineBreakMode = .byTruncatingTail
        let grip=NSTextField(labelWithString:"≡");grip.textColor = .secondaryLabelColor;grip.toolTip="Drag to reorder"
        let cell=NSView()
        for view in [check,name,grip] { cell.addSubview(view);view.translatesAutoresizingMaskIntoConstraints=false }
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:4),check.centerYAnchor.constraint(equalTo:cell.centerYAnchor),
            name.leadingAnchor.constraint(equalTo:check.trailingAnchor,constant:6),name.centerYAnchor.constraint(equalTo:cell.centerYAnchor),
            grip.leadingAnchor.constraint(greaterThanOrEqualTo:name.trailingAnchor,constant:8),grip.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-10),grip.centerYAnchor.constraint(equalTo:cell.centerYAnchor)
        ])
        return cell
    }
    @objc private func toggleApp(_ sender:NSButton) { entries[sender.tag].checked=sender.state == .on }
    @objc private func moveSelectedUp() { _=moveApp(from:table.selectedRow,toInsertionIndex:table.selectedRow-1) }
    @objc private func moveSelectedDown() { _=moveApp(from:table.selectedRow,toInsertionIndex:table.selectedRow+2) }
    @discardableResult func moveApp(from source:Int,toInsertionIndex insertion:Int)->Bool {
        guard entries.indices.contains(source),(0...entries.count).contains(insertion) else { return false }
        let destination=insertion > source ? insertion-1:insertion
        guard destination != source else { return false }
        let entry=entries.remove(at:source);entries.insert(entry,at:destination)
        table.reloadData();table.selectRowIndexes(IndexSet(integer:destination),byExtendingSelection:false);table.scrollRowToVisible(destination)
        return true
    }
    func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting? {
        let item=NSPasteboardItem();item.setString(entries[row].app.id,forType:dragType);return item
    }
    private func sourceRow(_ info:NSDraggingInfo)->Int? {
        guard let source=info.draggingSource as? NSTableView,source === table,let id=info.draggingPasteboard.string(forType:dragType) else { return nil }
        return entries.firstIndex(where:{$0.app.id == id})
    }
    func tableView(_ tableView:NSTableView,validateDrop info:NSDraggingInfo,proposedRow row:Int,proposedDropOperation operation:NSTableView.DropOperation)->NSDragOperation {
        guard sourceRow(info) != nil,(0...entries.count).contains(row) else { return [] }
        tableView.setDropRow(row,dropOperation:.above);return .move
    }
    func tableView(_ tableView:NSTableView,acceptDrop info:NSDraggingInfo,row:Int,dropOperation:NSTableView.DropOperation)->Bool {
        guard let source=sourceRow(info) else { return false }
        return moveApp(from:source,toInsertionIndex:row)
    }
}

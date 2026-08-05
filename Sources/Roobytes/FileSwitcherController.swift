import AppKit

@MainActor
protocol FileSwitcherDelegate: AnyObject {
    func fileSwitcher(_ switcher: FileSwitcherController, didSelectFile url: URL)
    func fileSwitcherDidCancel(_ switcher: FileSwitcherController)
}

/// Frosted “Go to File” overlay — frecency-ranked vault notes + fuzzy filter.
@MainActor
final class FileSwitcherController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    weak var delegate: FileSwitcherDelegate?

    private let panel = NSView()
    private let glass = NSVisualEffectView()
    private let tint = NSView()
    private let highlight = RoobytesGlassChrome.makeHighlightView()
    private let queryField = FileSwitcherQueryField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No matching notes")

    private var vaultURL: URL?
    private var currentFileURL: URL?
    private var allEntries: [VaultFileIndex.Entry] = []
    private var results: [URL] = []
    private var keyMonitor: Any?
    private var panelWidthConstraint: NSLayoutConstraint?
    private var panelHeightConstraint: NSLayoutConstraint?
    private var refilterWorkItem: DispatchWorkItem?

    private let maxVisibleRows = 10
    /// Cap ranked / fuzzy results — UI only shows ~10 rows; scanning thousands is wasted work.
    private let maxResultCount = 80
    private let refilterDebounce: TimeInterval = 0.05
    private let rowHeight: CGFloat = 26
    private let queryBandHeight: CGFloat = 44
    private let panelWidth: CGFloat = 480

    var isVisible: Bool { !view.isHidden }

    override func loadView() {
        let root = FileSwitcherRootView()
        root.wantsLayer = true
        root.panelProvider = { [weak self] in self?.panel }
        view = root
        view.isHidden = true

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.layer?.masksToBounds = false
        panel.shadow = NSShadow()
        panel.layer?.shadowOpacity = 0.32
        panel.layer?.shadowRadius = 16
        panel.layer?.shadowOffset = CGSize(width: 0, height: -3)

        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.material = .hudWindow
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.isEmphasized = true
        glass.wantsLayer = true
        glass.layer?.cornerRadius = RoobytesGlassChrome.cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true

        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.isBordered = false
        queryField.isBezeled = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.isEditable = true
        queryField.isSelectable = true
        let queryCell = VerticallyCenteredTextFieldCell(textCell: "")
        queryCell.isEditable = true
        queryCell.isSelectable = true
        queryCell.isScrollable = true
        queryCell.wraps = false
        queryCell.usesSingleLineMode = true
        queryCell.font = RoobytesFont.regular(size: 15)
        queryField.cell = queryCell
        queryField.font = RoobytesFont.regular(size: 15)
        queryField.placeholderString = "Go to file…"
        queryField.delegate = self
        queryField.onCancel = { [weak self] in
            self?.cancel()
        }

        let queryBand = NSView()
        queryBand.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableClicked(_:))
        tableView.doubleAction = #selector(tableDoubleClicked(_:))

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = RoobytesFont.regular(size: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let divider = NSView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor

        panel.addSubview(glass)
        glass.addSubview(tint)
        glass.addSubview(highlight)
        glass.addSubview(queryBand)
        queryBand.addSubview(queryField)
        glass.addSubview(divider)
        glass.addSubview(scrollView)
        glass.addSubview(emptyLabel)
        root.addSubview(panel)

        let width = panel.widthAnchor.constraint(equalToConstant: panelWidth)
        let height = panel.heightAnchor.constraint(equalToConstant: queryBandHeight + 8)
        panelWidthConstraint = width
        panelHeightConstraint = height

        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            panel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            width,
            height,
            panel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -40),

            glass.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            glass.topAnchor.constraint(equalTo: panel.topAnchor),
            glass.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            tint.topAnchor.constraint(equalTo: glass.topAnchor),
            tint.bottomAnchor.constraint(equalTo: glass.bottomAnchor),

            highlight.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            highlight.topAnchor.constraint(equalTo: glass.topAnchor),
            highlight.heightAnchor.constraint(equalToConstant: RoobytesGlassChrome.highlightHeight),

            queryBand.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            queryBand.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            queryBand.topAnchor.constraint(equalTo: glass.topAnchor),
            queryBand.heightAnchor.constraint(equalToConstant: queryBandHeight),

            queryField.leadingAnchor.constraint(equalTo: queryBand.leadingAnchor, constant: 16),
            queryField.trailingAnchor.constraint(equalTo: queryBand.trailingAnchor, constant: -16),
            queryField.centerYAnchor.constraint(equalTo: queryBand.centerYAnchor),
            queryField.heightAnchor.constraint(equalToConstant: 22),

            divider.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 10),
            divider.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -10),
            divider.topAnchor.constraint(equalTo: queryBand.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: glass.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        applyChrome()
    }

    func show(vault: URL, entries: [VaultFileIndex.Entry], currentFile: URL?) {
        vaultURL = vault
        currentFileURL = currentFile?.standardizedFileURL
        allEntries = entries
        queryField.stringValue = ""
        refilterWorkItem?.cancel()
        applyChrome()
        refilter()
        view.isHidden = false
        installKeyMonitor()
        focusQueryField()
        // ⌘P is a menu action — AppKit often restores the editor as first responder
        // after the action returns, so Normal-mode vim ate typing while ↑/↓ still
        // worked via the key monitor. Refocus on the next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.focusQueryField()
        }
    }

    /// Legacy entry used by tests / callers that only have URLs.
    func show(vault: URL, files: [URL], currentFile: URL?) {
        let entries = files.map {
            VaultFileIndex.Entry(
                url: $0.standardizedFileURL,
                displayPath: VaultFileIndex.relativeDisplayPath(for: $0, vault: vault)
            )
        }
        show(vault: vault, entries: entries, currentFile: currentFile)
    }

    private var isQueryEditing: Bool {
        guard let window = view.window else { return false }
        if window.firstResponder === queryField { return true }
        if let editor = queryField.currentEditor(), window.firstResponder === editor {
            return true
        }
        return false
    }

    private func focusQueryField() {
        guard let window = view.window else { return }
        _ = window.makeFirstResponder(queryField)
        queryField.selectText(nil)
    }

    func dismiss(notifyCancel: Bool = false) {
        refilterWorkItem?.cancel()
        removeKeyMonitor()
        view.isHidden = true
        queryField.stringValue = ""
        results = []
        tableView.reloadData()
        if notifyCancel {
            delegate?.fileSwitcherDidCancel(self)
        }
    }

    func refreshAccent() {
        applyChrome()
        tableView.reloadData()
    }

    // MARK: - Filter / ranking

    private func refilter() {
        guard vaultURL != nil else {
            results = []
            reloadResultsUI()
            return
        }
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            results = FileHistoryStore.shared
                .rankedEntries(allEntries, limit: maxResultCount)
                .map(\.url)
        } else {
            // Score every file once; keep top-N (no full frecency pre-sort).
            results = allEntries.compactMap { entry -> (URL, Double)? in
                guard let fuzzy = FuzzyMatcher.score(query: query, target: entry.displayPath) else {
                    return nil
                }
                let frecency = FileHistoryStore.shared.score(for: entry.url)
                return (entry.url, fuzzy * 1000 + frecency)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxResultCount)
            .map(\.0)
        }
        reloadResultsUI()
    }

    private func scheduleRefilter() {
        refilterWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refilter()
        }
        refilterWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + refilterDebounce, execute: work)
    }

    private func reloadResultsUI() {
        tableView.reloadData()
        emptyLabel.isHidden = !results.isEmpty
        scrollView.isHidden = results.isEmpty

        let rows = min(results.count, maxVisibleRows)
        let listHeight: CGFloat = results.isEmpty
            ? 40
            : CGFloat(rows) * (rowHeight + 2) + 8
        panelHeightConstraint?.constant = queryBandHeight + 10 + listHeight

        if results.isEmpty {
            return
        }

        var select = 0
        if queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let current = currentFileURL,
           let idx = results.firstIndex(of: current),
           results.count > 1
        {
            select = (idx + 1) % results.count
        }
        tableView.selectRowIndexes(IndexSet(integer: select), byExtendingSelection: false)
        tableView.scrollRowToVisible(select)
    }

    private func applyChrome() {
        RoobytesGlassChrome.apply(
            shell: panel,
            glass: glass,
            tint: tint,
            highlight: highlight,
            style: .panel
        )
        queryField.textColor = .labelColor
        queryField.font = RoobytesFont.regular(size: 15)
    }

    // MARK: - Navigation

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = (current + delta + results.count) % results.count
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        refreshRowColors()
    }

    private func confirmSelection() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        let url = results[row]
        dismiss(notifyCancel: false)
        delegate?.fileSwitcher(self, didSelectFile: url)
    }

    private func cancel() {
        dismiss(notifyCancel: true)
    }

    @objc private func tableClicked(_ sender: Any?) {
        refreshRowColors()
    }

    @objc private func tableDoubleClicked(_ sender: Any?) {
        confirmSelection()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else {
                return event
            }
            switch event.keyCode {
            case 53: // Esc
                self.cancel()
                return nil
            case 36, 76: // Return / Enter
                self.confirmSelection()
                return nil
            case 125: // Down
                self.moveSelection(1)
                return nil
            case 126: // Up
                self.moveSelection(-1)
                return nil
            case 51: // Delete / Backspace — keep editing the query even if focus drifted
                if !self.isQueryEditing {
                    self.focusQueryField()
                    if let fieldEditor = self.queryField.currentEditor() {
                        fieldEditor.deleteBackward(nil)
                        return nil
                    }
                }
                return event
            default:
                // Printable keys: if the editor stole focus, claim the query and
                // insert this stroke (otherwise Normal vim swallows it).
                if let chars = event.characters, chars.count == 1,
                   let ch = chars.first, ch != "\u{1b}", !ch.isNewline, ch != "\t"
                {
                    if !self.isQueryEditing {
                        self.focusQueryField()
                        if let fieldEditor = self.queryField.currentEditor() {
                            fieldEditor.insertText(chars)
                            return nil
                        }
                    }
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        scheduleRefilter()
    }

    /// Field editor eats ↑/↓ / Enter / Esc — intercept via doCommandBy, not `keyDown`.
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
            return true
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            confirmSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("SwitcherRow")
        if let existing = tableView.makeView(withIdentifier: id, owner: nil) as? RoobytesSidebarRowView {
            return existing
        }
        let rowView = RoobytesSidebarRowView()
        rowView.identifier = id
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("SwitcherCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
            ?? {
                let text = NSTextField(labelWithString: "")
                text.lineBreakMode = .byTruncatingMiddle
                text.font = RoobytesFont.regular(size: 13)
                text.drawsBackground = false
                text.isBordered = false
                let cell = NSTableCellView()
                cell.identifier = id
                cell.textField = text
                cell.addSubview(text)
                text.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell
            }()
        let url = results[row]
        let label: String
        if let vaultURL {
            label = VaultFileIndex.relativeDisplayPath(for: url, vault: vaultURL)
        } else {
            label = VaultFileIndex.stripMarkdownExtension(url.lastPathComponent)
        }
        cell.textField?.stringValue = label
        cell.textField?.font = RoobytesFont.regular(size: 13)
        cell.textField?.textColor = row == tableView.selectedRow ? RoobytesAccent.bright : .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshRowColors()
    }

    private func refreshRowColors() {
        let selected = tableView.selectedRow
        tableView.enumerateAvailableRowViews { _, row in
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView
            else { return }
            cell.textField?.textColor = row == selected ? RoobytesAccent.bright : .labelColor
        }
    }
}

/// Query field — ⌘P dismiss; navigation is handled by the controller’s doCommandBy + key monitor.
@MainActor
private final class FileSwitcherQueryField: NSTextField {
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘P while open dismisses (menu would toggle, but we own first responder).
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "p"
        {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Vertically centers single-line text / placeholder inside the query band.
private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let ideal = cellSize(forBounds: rect)
        var r = super.drawingRect(forBounds: rect)
        if rect.height > ideal.height {
            r.origin.y = rect.origin.y + ((rect.height - ideal.height) / 2)
            r.size.height = ideal.height
        }
        return r
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

/// Full-bleed host that only intercepts hits on the panel (clicks outside pass through).
@MainActor
private final class FileSwitcherRootView: NSView {
    var panelProvider: (() -> NSView?)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let panel = panelProvider?() else { return nil }
        if panel.frame.contains(point) {
            return super.hitTest(point)
        }
        return nil
    }
}

/// Accent-tinted selection pill for table rows.
@MainActor
final class RoobytesSidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let inset = bounds.insetBy(dx: 6, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        RoobytesAccent.color.withAlphaComponent(isEmphasized ? 0.34 : 0.22).setFill()
        path.fill()
    }

    override var isEmphasized: Bool {
        didSet { needsDisplay = true }
    }
}

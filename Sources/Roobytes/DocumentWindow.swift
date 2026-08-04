import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, EditorViewControllerDelegate, FileSwitcherDelegate {
    let editor = EditorViewController()
    let fileSwitcher = FileSwitcherController()
    private(set) var note = MarkdownDocument.empty()
    private(set) var folderURL: URL?
    private(set) var isPinned = false
    private var pinButton: NSButton?
    private var rssLabel: NSTextField?
    private var vimModeDot: NSImageView?
    private var memoryObserver: NSObjectProtocol?
    private let fileWatcher = FileWatcher()
    private var isSelfSaving = false
    private var isConfirmingDiscard = false

    /// - Parameter seedWelcome: When false (vault open on launch), start with an empty pristine buffer.
    convenience init(seedWelcome: Bool = true) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 640, height: 480)
        window.setFrameAutosaveName("Roobytes.DocumentWindow.v1")
        window.center()
        window.title = "Roobytes"
        window.isReleasedWhenClosed = false
        window.registerForDraggedTypes([.fileURL])
        self.init(window: window)
        if seedWelcome {
            note = .welcome()
        }
        window.delegate = self
        window.contentViewController = buildContent()
        installTitlebarAccessories()
        editor.delegate = self
        fileSwitcher.delegate = self
        fileWatcher.onChange = { [weak self] in
            self?.reloadIfExternallyChanged()
        }
        updateTitle()
        editor.applyDocument(note)
    }

    private func installTitlebarAccessories() {
        guard let window else { return }

        let modeDot = NSImageView()
        modeDot.imageScaling = .scaleProportionallyDown
        modeDot.translatesAutoresizingMaskIntoConstraints = false
        modeDot.setContentHuggingPriority(.required, for: .horizontal)
        modeDot.setContentHuggingPriority(.required, for: .vertical)
        modeDot.setContentCompressionResistancePriority(.required, for: .horizontal)
        vimModeDot = modeDot
        refreshVimModeDot()

        let mem = NSTextField(labelWithString: "Mem —")
        mem.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        mem.textColor = .secondaryLabelColor
        mem.alignment = .right
        mem.isEditable = false
        mem.isBordered = false
        mem.backgroundColor = .clear
        mem.drawsBackground = false
        mem.isBezeled = false
        mem.lineBreakMode = .byClipping
        mem.setContentHuggingPriority(.required, for: .horizontal)
        mem.setContentHuggingPriority(.required, for: .vertical)
        mem.translatesAutoresizingMaskIntoConstraints = false
        rssLabel = mem

        let button = NSButton(frame: .zero)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = "Keep Window Floating"
        button.target = self
        button.action = #selector(togglePin(_:))
        button.setButtonType(.toggle)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        pinButton = button
        updatePinButtonAppearance()

        let stack = NSStackView(views: [modeDot, mem, button])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let height: CGFloat = 28
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: height))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            modeDot.widthAnchor.constraint(equalToConstant: 10),
            modeDot.heightAnchor.constraint(equalToConstant: 10),
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)

        // Fit width to stack contents so the accessory doesn’t stretch oddly.
        container.frame.size.width = stack.fittingSize.width
        container.frame.size.height = height

        memoryObserver = NotificationCenter.default.addObserver(
            forName: MemoryMonitor.didUpdateNotification,
            object: MemoryMonitor.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTitlebarMem()
            }
        }
        refreshTitlebarMem()
    }

    private func refreshVimModeDot() {
        let mode = editor.vimMode
        let symbol: String
        let tint: NSColor
        switch mode {
        case .normal:
            symbol = "circle.fill"
            tint = RoobytesAccent.caret
        case .visual:
            symbol = "circle.lefthalf.filled"
            tint = RoobytesAccent.caret
        case .insert:
            symbol = "circle"
            tint = .tertiaryLabelColor
        }
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
        vimModeDot?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: mode.toolTip)?
            .withSymbolConfiguration(config)
        vimModeDot?.contentTintColor = tint
        vimModeDot?.toolTip = mode.toolTip
    }

    private func refreshTitlebarMem() {
        let mb = MemoryMonitor.shared.currentMegabytes
        let peak = MemoryMonitor.shared.peakMegabytes
        rssLabel?.stringValue = String(format: "Mem %.0f MB", mb)
        rssLabel?.toolTip = String(
            format: "Physical footprint %.0f MB (Activity Monitor) · peak %.0f MB",
            mb,
            peak
        )
        // Keep accessory width in sync as Mem string length changes.
        if let stack = vimModeDot?.superview as? NSStackView,
           let container = stack.superview
        {
            container.frame.size.width = max(stack.fittingSize.width, 120)
        }
    }

    @objc func togglePin(_ sender: Any?) {
        setPinned(!isPinned)
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        window?.level = pinned ? .floating : .normal
        updatePinButtonAppearance()
        RoobytesSettings.shared.isPinned = pinned
    }

    private func updatePinButtonAppearance() {
        guard let pinButton else { return }
        let name = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        pinButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Pin")?
            .withSymbolConfiguration(config)
        pinButton.contentTintColor = isPinned ? RoobytesAccent.color : NSColor.secondaryLabelColor
        pinButton.state = isPinned ? .on : .off
        pinButton.toolTip = isPinned ? "Unpin Window" : "Keep Window Floating"
    }

    private func buildContent() -> NSViewController {
        let root = NSViewController()
        let rootView = DropCatcherView(frame: .zero)
        rootView.controller = self
        root.view = rootView

        editor.view.translatesAutoresizingMaskIntoConstraints = false
        fileSwitcher.view.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(editor.view)
        rootView.addSubview(fileSwitcher.view)

        NSLayoutConstraint.activate([
            editor.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            editor.view.topAnchor.constraint(equalTo: rootView.topAnchor),
            editor.view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            fileSwitcher.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            fileSwitcher.view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            fileSwitcher.view.topAnchor.constraint(equalTo: rootView.topAnchor),
            fileSwitcher.view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        return root
    }

    /// Re-snapshot layer colors and restyle the editor after System/Light/Dark changes.
    func refreshAppearance() {
        window?.appearance = NSApp.appearance
        editor.refreshAppearance()
        fileSwitcher.refreshAccent()
        editor.refreshWordCompletionAccent()
        refreshVimModeDot()
        updatePinButtonAppearance()
    }

    /// Re-apply accent to chrome + live-restyle document colors.
    func refreshAccent() {
        refreshVimModeDot()
        updatePinButtonAppearance()
        editor.refreshAppearance()
        fileSwitcher.refreshAccent()
        editor.refreshWordCompletionAccent()
    }

    func showWindowBalanced() {
        showWindow(nil)
        DispatchQueue.main.async { [weak self] in
            self?.editor.focusEditor()
        }
    }

    // MARK: - Folder / File

    func openFolder(_ url: URL, preferredFile: URL? = nil) {
        guard confirmDiscardIfNeeded() else { return }
        let resolved = AppDelegate.resolvedVaultRoot(for: url)
        folderURL = resolved
        RoobytesSettings.shared.rememberOpened(file: nil, folder: resolved)

        if let preferred = preferredFile,
           FileManager.default.fileExists(atPath: preferred.path)
        {
            loadFile(preferred)
        } else if let first = VaultFileIndex.scan(root: resolved).first {
            loadFile(first)
        } else {
            note = MarkdownDocument(text: "", isDirty: false)
            editor.applyDocument(note)
            window?.representedURL = resolved
            updateTitle()
        }
    }

    func openFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        let preferredRoot = AppDelegate.resolvedVaultRoot(for: standardized)
        if let currentRoot = folderURL?.standardizedFileURL {
            let path = standardized.path
            let rootPath = currentRoot.path
            if path == rootPath || path.hasPrefix(rootPath + "/") {
                if currentRoot != preferredRoot {
                    guard confirmDiscardIfNeeded() else { return }
                    folderURL = preferredRoot
                    loadFile(standardized)
                    return
                }
                guard confirmDiscardIfNeeded() else { return }
                loadFile(standardized)
                return
            }
        }
        if folderURL?.standardizedFileURL != preferredRoot {
            guard confirmDiscardIfNeeded() else { return }
            folderURL = preferredRoot
        } else {
            guard confirmDiscardIfNeeded() else { return }
        }
        loadFile(standardized)
    }

    func newUntitled() {
        guard confirmDiscardIfNeeded() else { return }
        note = MarkdownDocument.untitled(in: folderURL)
        editor.applyDocument(note)
        window?.representedURL = folderURL
        updateTitle()
        editor.focusEditor()
    }

    /// - Returns: `true` when bytes were written (or Save As completed).
    @discardableResult
    func save() -> Bool {
        syncDocumentText()
        if note.url != nil {
            guard note.hasUserEdits || note.isDirty else { return false }
            do {
                isSelfSaving = true
                try note.save()
                fileWatcher.noteDidSave()
                isSelfSaving = false
                updateTitle()
                return true
            } catch {
                isSelfSaving = false
                showAlert(error)
                return false
            }
        } else {
            guard note.hasUserEdits || note.isDirty else { return false }
            return saveAs()
        }
    }

    /// - Returns: `true` when the user confirmed and the file was written.
    @discardableResult
    func saveAs() -> Bool {
        syncDocumentText()
        let panel = NSSavePanel()
        panel.allowedContentTypes = MarkdownDocument.markdownContentTypes
        panel.nameFieldStringValue = note.displayName
        if let folderURL {
            panel.directoryURL = folderURL
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            isSelfSaving = true
            try note.save(to: url)
            fileWatcher.watch(url)
            isSelfSaving = false
            if folderURL == nil {
                folderURL = url.deletingLastPathComponent()
            }
            window?.representedURL = url
            updateTitle()
            RoobytesSettings.shared.rememberOpened(file: url, folder: folderURL ?? url.deletingLastPathComponent())
            FileHistoryStore.shared.record(url: url)
            return true
        } catch {
            isSelfSaving = false
            showAlert(error)
            return false
        }
    }

    var isDocumentDirty: Bool {
        note.hasUserEdits
    }

    /// Whether the buffer has real user edits that should prompt before discard.
    var needsDiscardConfirmation: Bool {
        note.hasUserEdits
    }

    // MARK: - File switcher

    func showFileSwitcher() {
        guard let folderURL else {
            let alert = NSAlert()
            alert.messageText = "No vault open"
            alert.informativeText = "Open a folder first (⇧⌘O), then use Go to File."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        editor.dismissCommandPalette()
        let files = VaultFileIndex.scan(root: folderURL)
        // Drop editor focus before showing — menu ⌘P otherwise leaves Normal vim
        // as first responder and typing never reaches the query field.
        window?.makeFirstResponder(nil)
        fileSwitcher.show(vault: folderURL, files: files, currentFile: note.url)
    }

    func dismissFileSwitcher(focusEditor: Bool = true) {
        guard fileSwitcher.isVisible else { return }
        fileSwitcher.dismiss(notifyCancel: false)
        if focusEditor {
            editor.focusEditor()
        }
    }

    var isFileSwitcherVisible: Bool { fileSwitcher.isVisible }

    func showFind() {
        editor.showFind()
    }

    func showRandomTip() {
        editor.showRandomTip()
    }

    func toggleBold() { editor.toggleBold() }
    func toggleItalic() { editor.toggleItalic() }
    func toggleTask() { editor.toggleTask() }
    var canToggleTask: Bool { editor.canToggleTask }
    func markTaskDone() { editor.markTaskDone() }
    var canMarkTaskDone: Bool { editor.canMarkTaskDone }
    func markTaskOpen() { editor.markTaskOpen() }
    var canMarkTaskOpen: Bool { editor.canMarkTaskOpen }
    func toggleFocusTask() { editor.toggleFocusTask() }
    var canToggleFocusTask: Bool { editor.canToggleFocusTask }
    func openURLUnderCaret(privateBrowsing: Bool) { editor.openURLUnderCaret(privateBrowsing: privateBrowsing) }
    func applyHeading(_ level: Int) { editor.applyHeading(level) }
    func applyBody() { editor.applyBody() }
    func applyBulletList() { editor.applyBulletList() }

    // MARK: - Delegates

    func editorDidChangeText(_ editor: EditorViewController) {
        note.updateText(editor.currentText, userEdit: true)
        updateTitle()
    }

    func editorDidChangeVimMode(_ editor: EditorViewController) {
        refreshVimModeDot()
    }

    func editorRequestSave(_ editor: EditorViewController) -> Bool {
        save()
    }

    func editorRequestQuit(_ editor: EditorViewController) {
        window?.performClose(nil)
    }

    func editorRequestTogglePin(_ editor: EditorViewController) -> Bool {
        setPinned(!isPinned)
        return isPinned
    }

    /// `:e!` / `:discard` — reload from disk, or reset an untitled buffer.
    func editorRequestDiscard(_ editor: EditorViewController) -> String? {
        syncDocumentText()
        guard note.hasUserEdits else {
            return "No changes"
        }

        if let url = note.url {
            do {
                let doc = MarkdownDocument()
                try doc.load(from: url)
                note = doc
                editor.applyDocument(note)
                note.replaceTextWithoutMarkingDirty(editor.pullSyncedText())
                fileWatcher.noteDidSave()
                window?.representedURL = url
                updateTitle()
                editor.focusEditor()
                return "Discarded"
            } catch {
                showAlert(error)
                return nil
            }
        }

        // Untitled — drop edits back to a clean blank untitled.
        note = MarkdownDocument(text: "# Untitled\n\n", isDirty: false, hasUserEdits: false)
        editor.applyDocument(note)
        window?.representedURL = folderURL
        updateTitle()
        editor.focusEditor()
        return "Discarded"
    }

    /// `:daily` / `:today` — open or create today’s note from the vault daily template.
    func editorRequestDailyNote(_ editor: EditorViewController) -> String? {
        guard let folderURL else {
            return "No vault open — Open Folder… (⇧⌘O) first"
        }
        do {
            let url = try DailyNotes.ensureTodaysNote(vault: folderURL)
            openFile(url)
            return nil
        } catch DailyNotes.EnsureError.templateMissing {
            let installed = DailyNotesTemplateSetup.presentMissingTemplateAlert(
                vault: folderURL,
                window: window
            )
            guard installed else {
                return "Missing \(DailyNotes.templateFileName) — set up a template to use :daily"
            }
            do {
                let url = try DailyNotes.ensureTodaysNote(vault: folderURL)
                openFile(url)
                return nil
            } catch DailyNotes.EnsureError.writeFailed(let detail) {
                return "Daily note failed: \(detail)"
            } catch {
                return "Daily note failed"
            }
        } catch DailyNotes.EnsureError.writeFailed(let detail) {
            return "Daily note failed: \(detail)"
        } catch {
            return "Daily note failed"
        }
    }

    func editorWillBeginCommandPalette(_ editor: EditorViewController) {
        dismissFileSwitcher(focusEditor: false)
    }

    func fileSwitcher(_ switcher: FileSwitcherController, didSelectFile url: URL) {
        if note.url?.standardizedFileURL == url.standardizedFileURL {
            editor.focusEditor()
            return
        }
        guard confirmDiscardIfNeeded() else {
            editor.focusEditor()
            return
        }
        loadFile(url)
    }

    func fileSwitcherDidCancel(_ switcher: FileSwitcherController) {
        editor.focusEditor()
    }

    // MARK: - Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        syncDocumentText()
        guard note.hasUserEdits else { return true }
        confirmDiscardWithSheet { [weak self] proceed in
            guard proceed else { return }
            // `close()` skips `windowShouldClose`, so the sheet's answer is final.
            self?.window?.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        dismissFileSwitcher(focusEditor: false)
        fileWatcher.stop()
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
            self.memoryObserver = nil
        }
        AppDelegate.shared?.removeWindow(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if fileWatcher.checkForExternalChange() {
            reloadIfExternallyChanged()
        }
    }

    // MARK: - Drag & drop on window

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canAcceptDrop(sender) ? .copy : []
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first
        else { return false }
        openDroppedURL(url)
        return true
    }

    func openDroppedURL(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            openFolder(url)
        } else if MarkdownDocument.isMarkdownFile(url) {
            openFile(url)
        }
    }

    // MARK: - Private

    private func loadFile(_ url: URL) {
        do {
            let doc = MarkdownDocument()
            try doc.load(from: url)
            note = doc
            editor.applyDocument(note)
            note.replaceTextWithoutMarkingDirty(editor.pullSyncedText())
            window?.representedURL = url
            updateTitle()
            editor.focusEditor()
            fileWatcher.watch(url)
            RoobytesSettings.shared.rememberOpened(file: url, folder: folderURL ?? url.deletingLastPathComponent())
            FileHistoryStore.shared.record(url: url)
        } catch {
            showAlert(error)
        }
    }

    private func reloadIfExternallyChanged() {
        guard !isSelfSaving else { return }
        guard let url = note.url else { return }
        guard !note.hasUserEdits else { return }
        guard editor.vimMode == .normal else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let fresh = try String(contentsOf: url, encoding: .utf8)
            guard fresh != editor.currentText else { return }
            RoobytesDebugLog.event("file-watcher reload \(url.lastPathComponent) (\(fresh.count) chars)")
            let doc = MarkdownDocument()
            try doc.load(from: url)
            note = doc
            editor.applyDocument(note, preserveScroll: true)
            updateTitle()
        } catch {}
    }

    private func syncDocumentText() {
        // Round-trip sync must not count as a user edit (WYSIWYG ↔ markdown).
        note.updateText(editor.pullSyncedText(), userEdit: false)
    }

    /// Save / discard confirmation as a window sheet, so the rest of the app stays live.
    /// `proceed` is true once the edits are written or deliberately dropped.
    func confirmDiscardWithSheet(_ proceed: @escaping (Bool) -> Void) {
        syncDocumentText()
        guard note.hasUserEdits else { return proceed(true) }
        guard let window else { return proceed(confirmDiscardIfNeeded()) }
        guard !isConfirmingDiscard else { return proceed(false) }

        isConfirmingDiscard = true
        let alert = discardAlert()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return proceed(false) }
            self.isConfirmingDiscard = false
            switch response {
            case .alertFirstButtonReturn:
                self.save()
                proceed(!self.note.hasUserEdits)
            case .alertSecondButtonReturn:
                proceed(true)
            default:
                // Esc lands here. Say so — a vim reflex otherwise looks like a dead `:q`.
                self.editor.flashCommandLineMessage("Close cancelled — :w saves, then :q")
                proceed(false)
            }
        }
    }

    private func discardAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes you made to “\(note.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    /// Blocking variant, still used by the in-place file / folder swaps.
    @discardableResult
    private func confirmDiscardIfNeeded() -> Bool {
        syncDocumentText()
        guard note.hasUserEdits else { return true }
        switch discardAlert().runModal() {
        case .alertFirstButtonReturn:
            save()
            return !note.hasUserEdits
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func updateTitle() {
        // No dirty "• " prefix — macOS document-edited dot covers that; strip filename emoji noise.
        let name = Self.titleText(from: note.displayName)
        if let folderURL {
            let folder = folderURL.lastPathComponent
            window?.title = "\(name) — \(folder)"
        } else {
            window?.title = "\(name) — Roobytes"
        }
        window?.isDocumentEdited = note.hasUserEdits
        // Hide the document icon proxy (reads as an extra glyph before the name).
        window?.standardWindowButton(.documentIconButton)?.isHidden = true
    }

    /// Display title without emoji / pictographs (files keep their real names on disk).
    private static func titleText(from fileName: String) -> String {
        let pattern = try? NSRegularExpression(
            pattern: #"\p{Extended_Pictographic}|\p{Emoji_Presentation}|[\u{FE0F}\u{20E3}]"#
        )
        let range = NSRange(fileName.startIndex..., in: fileName)
        var stripped = pattern?.stringByReplacingMatches(
            in: fileName,
            range: range,
            withTemplate: ""
        ) ?? fileName
        stripped = stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? fileName : stripped
    }

    private func showAlert(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func canAcceptDrop(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first
        else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue || MarkdownDocument.isMarkdownFile(url)
    }
}

/// Window content that forwards file drops to the controller.
@MainActor
final class DropCatcherView: NSView {
    weak var controller: DocumentWindowController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.draggingEntered(sender) ?? []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.performDragOperation(sender) ?? false
    }
}

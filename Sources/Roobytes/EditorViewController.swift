import AppKit
import QuartzCore

@MainActor
protocol EditorViewControllerDelegate: AnyObject {
    func editorDidChangeText(_ editor: EditorViewController)
    func editorDidChangeVimMode(_ editor: EditorViewController)
    func editorRequestSave(_ editor: EditorViewController) -> Bool
    func editorRequestQuit(_ editor: EditorViewController)
    func editorRequestTogglePin(_ editor: EditorViewController) -> Bool
    /// Discard unsaved edits (reload from disk, or reset untitled). Returns flash message.
    func editorRequestDiscard(_ editor: EditorViewController) -> String?
    /// Open or create today’s daily note. Returns flash message on failure (nil on success).
    func editorRequestDailyNote(_ editor: EditorViewController) -> String?
    func editorWillBeginCommandPalette(_ editor: EditorViewController)
}

@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {
    weak var delegate: EditorViewControllerDelegate?

    let textView = RoobytesEditorTextView()
    let scrollView = NSScrollView()
    let lineNumberGutter = LineNumberGutterView()
    var isApplyingDocument = false
    var vimMode: VimEditorMode = .normal
    var markdownSource = "" {
        didSet {
            cachedMarkdownLines = nil
            wordIndexDirty = true
            markdownRevision &+= 1
        }
    }
    var markdownRevision: Int = 0
    /// Lazily-split lines of `markdownSource`; invalidated on every mutation.
    var cachedMarkdownLines: [String]?
    var markdownLines: [String] {
        if let cached = cachedMarkdownLines { return cached }
        let lines = markdownSource.components(separatedBy: "\n")
        cachedMarkdownLines = lines
        return lines
    }
    var wordIndexDirty = true
    var restyleWorkItem: DispatchWorkItem?
    /// Live Preview: caret line rendered as raw markdown.
    var activeSourceLine: Int?
    var isSnappingCaret = false
    var isUpdatingBlockCaret = false
    /// Pending first key of a two-key Normal command (e.g. `z` waiting for `zz`, `d` for `dd`).
    var pendingVimKey: Character?
    /// Characterwise Visual anchor (UTF-16); set while `vimMode == .visual`.
    var visualAnchor: Int?
    /// Characterwise Visual active end (UTF-16); motions update this.
    var visualCaret: Int?
    /// Vim count prefix (`5j`, `3dd`). `0` means no count (treated as 1).
    var vimCount: Int = 0
    /// Sticky vertical-motion goal — `x` for display-row `j`/`k`, `column` for counted
    /// logical moves; the last vertical motion owns it. Valid only while the caret is
    /// still at `vimVerticalGoalAnchor`, so any other motion or edit drops it without
    /// every call site having to opt in.
    var vimVerticalGoalX: CGFloat?
    var vimVerticalGoalColumn: Int?
    var vimVerticalGoalAnchor: Int?
    /// Yank register for `dd` / `yy` / Visual `y`/`d` / `p` / `P`.
    var vimYankLines: String?
    /// Whether `vimYankLines` was filled linewise (`dd`/`yy`) or characterwise (Visual `y`/`d`).
    var vimYankKind: VimYankKind = .linewise
    /// Vim `:` command-line buffer (includes leading `:`).
    var vimCommandLine: String?
    let commandPalette = EditorCommandPalette()
    var isVimHelpVisible = false
    var isTipVisible = false
    var isVimChordHintVisible = false
    let visualModeBadge = VisualModeBadge()
    var gutterWidthConstraint: NSLayoutConstraint?
    /// Stored for removal in `deinit` (nonisolated).
    private nonisolated(unsafe) var scrollBoundsObserver: NSObjectProtocol?
    private nonisolated(unsafe) var wordCompletionObserver: NSObjectProtocol?
    private nonisolated(unsafe) var spellCheckingObserver: NSObjectProtocol?
    var lineIndexCache = LineIndexCache()
    var viewTextRevision: Int = 0
    var sourceLineParagraphIndex: MarkdownBridge.SourceLineParagraphIndex?
    var sourceLineParagraphIndexRevision: Int = -1
    var lastOverscrollVisibleHeight: CGFloat = 0
    /// Transient “where was I” / “where am I” caret feedback layers.
    var caretGhostLayer: CALayer?
    var caretPulseLayer: CALayer?
    var caretFeedbackGeneration: UInt64 = 0
    /// Last successful restyle snapshot — enables incremental active-line swaps.
    var lastRestyleMarkdownRevision: Int = -1
    /// Line count at last restyle — incremental replace is unsafe after insert/delete joins.
    var lastRestyleMarkdownLineCount: Int = 0
    var lastRestyleActiveLine: Int? = nil
    var lastRestyleHadCodeFence = false
    /// Session-only nested-list folds (parent markdown line indices). Cleared on load / structural edits.
    var foldedParentLines: Set<Int> = []
    /// Insert-mode buffer word completion (LazyVim-style).
    var wordIndex = BufferWordIndex()
    let wordCompletion = WordCompletionMenu()

    func ensureWordIndex() {
        guard wordIndexDirty else { return }
        wordIndex.rebuild(from: markdownSource)
        wordIndexDirty = false
    }

    var editorTextView: NSTextView { textView }

    override func loadView() {
        configureScroll()
        textView.vimHost = self
        textView.delegate = self
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = RoobytesSettings.shared.spellChecking
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 14, height: 18)
        textView.importsGraphics = false
        applyModeChrome()

        let root = NSView()
        root.postsFrameChangedNotifications = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        lineNumberGutter.translatesAutoresizingMaskIntoConstraints = false
        lineNumberGutter.textView = textView
        lineNumberGutter.scrollView = scrollView

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lineNumberGutter.setNeedsDisplayForScrollIfNeeded()
            }
        }

        root.addSubview(lineNumberGutter)
        root.addSubview(scrollView)

        let gutterW = lineNumberGutter.widthAnchor.constraint(
            equalToConstant: lineNumberGutter.preferredWidth(forLineCount: 1)
        )
        gutterWidthConstraint = gutterW

        NSLayoutConstraint.activate([
            lineNumberGutter.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            lineNumberGutter.topAnchor.constraint(equalTo: root.topAnchor),
            lineNumberGutter.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            gutterW,

            scrollView.leadingAnchor.constraint(equalTo: lineNumberGutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        commandPalette.install(in: root, alignedTo: scrollView)
        commandPalette.onScrimClick = { [weak self] in
            self?.hideVimHelp()
        }
        visualModeBadge.install(in: root, alignedTo: scrollView)
        wordCompletion.install(in: root)
        wordCompletionObserver = NotificationCenter.default.addObserver(
            forName: .roobytesWordCompletionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !RoobytesSettings.shared.wordCompletion {
                    self.hideWordCompletion()
                } else if self.vimMode == .insert {
                    self.refreshWordCompletion()
                }
            }
        }
        spellCheckingObserver = NotificationCenter.default.addObserver(
            forName: .roobytesSpellCheckingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.textView.isContinuousSpellCheckingEnabled = RoobytesSettings.shared.spellChecking
                self.refreshSpellChecking()
            }
        }
        view = root
        updateLineNumberGutter()
    }

    deinit {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
        }
        if let wordCompletionObserver {
            NotificationCenter.default.removeObserver(wordCompletionObserver)
        }
        if let spellCheckingObserver {
            NotificationCenter.default.removeObserver(spellCheckingObserver)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        updateBottomOverscrollPadding()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateBottomOverscrollPadding()
    }

    func applyDocument(_ document: MarkdownDocument, preserveScroll: Bool = false) {
        let savedScrollY = scrollView.contentView.bounds.origin.y
        let savedSelection = textView.selectedRange()

        restyleWorkItem?.cancel()
        clearCaretFeedback()
        activeSourceLine = nil
        clearListFolds()
        lastRestyleMarkdownRevision = -1
        lastRestyleMarkdownLineCount = 0
        lastRestyleActiveLine = nil
        lastRestyleHadCodeFence = false
        sourceLineParagraphIndex = nil
        sourceLineParagraphIndexRevision = -1
        markdownSource = document.text
        hideWordCompletion()
        isApplyingDocument = true
        renderCurrentMode()
        isApplyingDocument = false
        textView.breakUndoCoalescing()
        // Launch / open always lands in Normal (Live Preview), not Insert.
        if vimMode != .normal {
            setVimMode(.normal)
        } else {
            refreshBlockCaret()
            delegate?.editorDidChangeVimMode(self)
        }
        updateLineNumberGutter()

        if preserveScroll {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let maxLoc = self.textView.string.utf16.count
                let clampedLoc = min(savedSelection.location, maxLoc)
                self.isSnappingCaret = true
                self.textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
                self.isSnappingCaret = false
                self.scrollDocument(toY: savedScrollY, animated: false)
                if self.vimMode == .normal { self.refreshBlockCaret() }
                self.updateLineNumberGutter()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.revealFocusedTaskIfPresent() {
                    self.scrollDocument(toY: 0, animated: false)
                }
            }
        }
    }

    /// If the note has a `[!]` task, place the caret on it and center it in the viewport.
    @discardableResult
    func revealFocusedTaskIfPresent() -> Bool {
        let lines = markdownLines
        guard let lineIdx = MarkdownBridge.focusTaskLineIndex(in: lines) else {
            return false
        }
        guard lineIdx >= 0, lineIdx < lines.count else { return false }
        let col = MarkdownBridge.contentStartColumn(in: lines[lineIdx])
        let caret = MarkdownBridge.MarkdownCaret(line: lineIdx, column: col)

        let attributed: NSAttributedString
        if let storage = textView.textStorage {
            attributed = storage
        } else {
            attributed = NSAttributedString(string: textView.string)
        }

        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        refreshSourceLineParagraphIndexIfNeeded()

        let loc = MarkdownBridge.attributedLocation(
            for: caret,
            attributed: attributed,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        isSnappingCaret = true
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        isSnappingCaret = false
        if vimMode == .normal {
            refreshBlockCaret()
        }
        vimCenterCursorLine()
        updateLineNumberGutter()
        return true
    }


    var currentText: String {
        // Prefer the already-synced source. Callers that need a fresh pull
        // (save / mode switch / load canonicalize) use `pullSyncedText()`.
        markdownSource
    }

    /// Sync the text view into `markdownSource` and return it.
    func pullSyncedText() -> String {
        syncMarkdownFromView()
        return markdownSource
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
        let loc = textView.selectedRange().location
        if !isCharacterVisible(loc, padding: 24) {
            scrollCharacterIntoViewInstant(loc, padding: 40)
        }
    }

    /// Dismiss the vim `:` command palette if open.
    func dismissCommandPalette() {
        endVimCommandLine()
        hideVimHelp()
        hideTip()
        hideVimChordHint()
    }

    /// Whether the vim command palette is capturing keys.
    var isCommandPaletteActive: Bool {
        vimCommandLine != nil || isVimHelpVisible || isTipVisible
    }

    /// Show a random tip (startup / `:tips`).
    func showRandomTip() {
        showTip()
    }

    func showFind() {
        textView.performFindPanelAction(self)
    }

    func toggleBold() {
        MarkdownBridge.toggleTrait(.boldFontMask, on: textView)
        restylePreservingMarkdownCaret(delay: 0.05)
    }

    func toggleItalic() {
        MarkdownBridge.toggleTrait(.italicFontMask, on: textView)
        restylePreservingMarkdownCaret(delay: 0.05)
    }

    func applyHeading(_ level: Int) {
        let block: MDBlock
        switch level {
        case 1: block = .h1
        case 2: block = .h2
        case 3: block = .h3
        default: block = .h4
        }
        MarkdownBridge.applyBlock(block, to: textView)
        restylePreservingMarkdownCaret(delay: 0.05)
    }

    func applyBody() {
        MarkdownBridge.applyBlock(.paragraph, to: textView)
        restylePreservingMarkdownCaret(delay: 0.05)
    }

    func applyBulletList() {
        MarkdownBridge.applyBlock(.bullet, to: textView)
        ensureBulletPrefix()
        restylePreservingMarkdownCaret(delay: 0.05)
    }


    func textDidChange(_ notification: Notification) {
        guard !isApplyingDocument else { return }
        viewTextRevision &+= 1
        sourceLineParagraphIndex = nil
        sourceLineParagraphIndexRevision = -1
        // Insert + active line: patch markdown only — never reverse-convert or full restyle.
        if let active = activeSourceLine {
            syncLineAtIndex(active)
            delegate?.editorDidChangeText(self)
            updateLineNumberGutter()
            refreshWordCompletion()
            return
        }
        syncMarkdownFromView()
        delegate?.editorDidChangeText(self)
        updateLineNumberGutter()
        hideWordCompletion()
        restylePreservingMarkdownCaret(delay: 0.12)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingDocument, !isSnappingCaret, !isUpdatingBlockCaret else { return }
        updateLineNumberGutter()
        if vimMode == .normal {
            // Normal = full Live Preview (no raw caret line) — only keep the block caret.
            refreshBlockCaret()
            return
        }
        if vimMode == .visual {
            // Keep the AppKit selection; do not activate a raw Insert line.
            return
        }
        snapTaskLineCaretIfNeeded()
        updateActiveSourceLineFromSelection()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Esc → cancelOperation:. Own it so AppKit never chains into edits.
        if commandSelector == #selector(cancelOperation(_:)) {
            handleVimEscape()
            return true
        }
        if vimMode == .normal {
            // Edits are blocked in RoobytesEditorTextView.doCommand; still own Enter if it slips through.
            if commandSelector == #selector(insertNewline(_:))
                || commandSelector == #selector(insertNewlineIgnoringFieldEditor(_:))
                || commandSelector == #selector(insertTab(_:))
                || commandSelector == #selector(deleteBackward(_:))
                || commandSelector == #selector(deleteForward(_:))
            {
                return true
            }
        }
        // Insert word completion: Tab / Enter accept when the menu is up.
        if vimMode == .insert, wordCompletion.isVisible {
            if commandSelector == #selector(insertTab(_:)) {
                acceptWordCompletion()
                return true
            }
            if commandSelector == #selector(insertNewline(_:))
                || commandSelector == #selector(insertNewlineIgnoringFieldEditor(_:))
            {
                acceptWordCompletion()
                return true
            }
            if commandSelector == #selector(moveUp(_:)) {
                wordCompletion.moveSelection(-1)
                if let anchors = wordCompletionAnchorsForCurrentPrefix() {
                    wordCompletion.updateGhost(originInHost: anchors.ghost)
                }
                return true
            }
            if commandSelector == #selector(moveDown(_:)) {
                wordCompletion.moveSelection(1)
                if let anchors = wordCompletionAnchorsForCurrentPrefix() {
                    wordCompletion.updateGhost(originInHost: anchors.ghost)
                }
                return true
            }
        }
        if commandSelector == #selector(insertNewline(_:))
            || commandSelector == #selector(insertNewlineIgnoringFieldEditor(_:))
        {
            RoobytesDebugLog.event(
                "doCommand newline sel=\(NSStringFromSelector(commandSelector)) mode=\(vimMode == .normal ? "normal" : "insert")"
            )
            if vimMode == .insert {
                TypewriterSound.shared.playInsert("\n")
            }
            hideWordCompletion()
            insertNewlineContinuingList()
            return true // we own the edit — avoids view/md line-count desync
        }
        return false
    }




























    private func applyModeChrome() {
        textView.backgroundColor = RoobytesTheme.editorBackground
        textView.insertionPointColor = RoobytesAccent.caret
        textView.selectedTextAttributes = RoobytesAccent.selectionAttributes
        textView.isRichText = true
        textView.usesFontPanel = false
    }

    /// Re-apply chrome and re-render after System / Light / Dark changes.
    func refreshAppearance() {
        MarkdownBridge.invalidateCheckboxImageCache()
        applyModeChrome()
        applyCommandPaletteChrome(message: vimCommandLine == nil && !commandPalette.isHidden)
        visualModeBadge.refreshAppearance()
        liveRestylePreservingMarkdownCaret()
        scrollView.needsDisplay = true
        textView.needsDisplay = true
        updateLineNumberGutter()
    }

    private func configureScroll() {
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
        textView.isEditable = true
        textView.isSelectable = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        updateBottomOverscrollPadding()
    }

}

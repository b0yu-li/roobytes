import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    /// Vim Normal `'f` — jump to the focused `[!]` task (mark-`f` shaped; not a full mark system yet).
    func vimGoToFocusedTask() {
        syncMarkdownFromView()
        if revealFocusedTaskIfPresent() { return }
        flashCommandLineMessage("No focus task")
        NSSound.beep()
    }

    /// Vim Normal `]t` / `[t` — next / previous undone (`[ ]` / `[!]`) task.
    func vimJumpUndoneTask(forward: Bool, count: Int) {
        clearVimPrefix()
        syncMarkdownFromView()
        let lines = markdownLines
        let from = caretLineIndex()
        let target: Int?
        if forward {
            target = MarkdownBridge.nextUndoneTaskLine(from: from, count: count, in: lines)
        } else {
            target = MarkdownBridge.previousUndoneTaskLine(from: from, count: count, in: lines)
        }
        guard let lineIdx = target, lineIdx >= 0, lineIdx < lines.count else {
            flashCommandLineMessage(forward ? "No next undone task" : "No previous undone task")
            NSSound.beep()
            refreshBlockCaret()
            return
        }
        let col = MarkdownBridge.contentStartColumn(in: lines[lineIdx])
        activeSourceLine = nil
        let caret = MarkdownBridge.MarkdownCaret(line: lineIdx, column: col)
        liveRestyle(to: caret, animateScroll: false)
        vimCenterCursorLine()
        refreshBlockCaret()
        updateLineNumberGutter()
    }

    /// Vim Normal `u` / `3u` — undo via the text view’s undo manager.
    func vimUndo(times: Int) {
        guard let undo = textView.undoManager else {
            flashCommandLineMessage("Nothing to undo")
            NSSound.beep()
            return
        }
        var undid = 0
        for _ in 0..<max(1, times) {
            guard undo.canUndo else { break }
            undo.undo()
            undid += 1
        }
        guard undid > 0 else {
            flashCommandLineMessage("Already at oldest change")
            NSSound.beep()
            return
        }
        // Undo may not always go through `textDidChange` the same path — sync + restyle.
        syncMarkdownFromView()
        delegate?.editorDidChangeText(self)
        updateLineNumberGutter()
        liveRestyle(to: currentMarkdownCaret(), animateScroll: false)
        if vimMode == .normal {
            refreshBlockCaret()
        }
    }

    /// Vim Normal `gx` / `gX` — open URL under caret in Firefox (normal / Private).
    func openURLUnderCaret(privateBrowsing: Bool) {
        vimOpenURLUnderCaret(privateBrowsing: privateBrowsing)
    }

    /// Vim Normal `gx` / `gX` — open URL under caret in Firefox (normal / Private).
    func vimOpenURLUnderCaret(privateBrowsing: Bool) {
        syncMarkdownFromView()
        let caret = currentMarkdownCaret()
        let lines = markdownLines
        guard caret.line >= 0, caret.line < lines.count else {
            flashCommandLineMessage("No URL under caret")
            NSSound.beep()
            return
        }
        guard let url = URLUnderCaret.url(in: lines[caret.line], column: caret.column) else {
            flashCommandLineMessage("No URL under caret")
            NSSound.beep()
            return
        }
        switch BrowserLauncher.open(url, privateBrowsing: privateBrowsing) {
        case .success:
            break
        case .failure(.openFailed):
            flashCommandLineMessage("Could not open URL")
            NSSound.beep()
        }
    }

    /// Vim Normal `K` — system Dictionary / Look Up for the word under the caret.
    func vimLookupWordUnderCaret() {
        clearVimPrefix()
        let ns = textView.string as NSString
        let loc = textView.selectedRange().location
        guard let range = WordUnderCaret.range(in: ns, at: loc) else {
            flashCommandLineMessage("No word under caret")
            NSSound.beep()
            return
        }
        let word = ns.substring(with: range)
        let attrs = textView.typingAttributes
        let attributed = NSAttributedString(string: word, attributes: attrs)
        guard let origin = definitionBaselineOrigin(forCharacterRange: range) else {
            flashCommandLineMessage("No word under caret")
            NSSound.beep()
            return
        }
        textView.showDefinition(for: attributed, at: origin)
    }

    /// Vim Normal `z=` — apply the first macOS spelling guess for the word under the caret.
    func vimAutoFixSpellingUnderCaret() {
        clearVimPrefix()
        syncMarkdownFromView()
        var caret = currentMarkdownCaret()
        var lines = markdownLines
        guard caret.line >= 0, caret.line < lines.count else {
            flashCommandLineMessage("No word under caret")
            NSSound.beep()
            refreshBlockCaret()
            return
        }

        let line = lines[caret.line]
        let ns = line as NSString
        guard let wordRange = WordUnderCaret.range(in: ns, at: caret.column) else {
            flashCommandLineMessage("No word under caret")
            NSSound.beep()
            refreshBlockCaret()
            return
        }

        let word = ns.substring(with: wordRange)
        let checker = NSSpellChecker.shared
        let language = checker.language()
        let guesses = checker.guesses(
            forWordRange: wordRange,
            in: line,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        guard let fix = guesses.first, fix != word else {
            flashCommandLineMessage("No suggestions")
            NSSound.beep()
            refreshBlockCaret()
            return
        }

        let updated = ns.replacingCharacters(in: wordRange, with: fix)
        lines[caret.line] = updated
        markdownSource = lines.joined(separator: "\n")
        caret.column = wordRange.location + (fix as NSString).length - 1

        activeSourceLine = nil
        liveRestyle(to: caret, animateScroll: false)
        refreshBlockCaret()
        updateLineNumberGutter()
        delegate?.editorDidChangeText(self)
        flashCommandLineMessage("Fixed → \(fix)")
    }

    /// Baseline origin in text-view coordinates for `showDefinition(for:at:)`.
    private func definitionBaselineOrigin(forCharacterRange range: NSRange) -> NSPoint? {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              range.length > 0
        else { return nil }
        let storageLen = textView.textStorage?.length ?? textView.string.utf16.count
        guard range.location < storageLen else { return nil }

        layoutManager.ensureLayout(for: container)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let locInFragment = layoutManager.location(forGlyphAt: glyphIndex)
        let origin = textView.textContainerOrigin
        return NSPoint(
            x: fragment.origin.x + locInFragment.x + origin.x,
            y: fragment.origin.y + locInFragment.y + origin.y
        )
    }
    /// Toggle task marker on the caret’s task line (⌘↩): `[ ]`/`[!]` → `[x]` → `[~]` → `[ ]`.
    @discardableResult
    func toggleTask() -> Bool {
        mutateCaretMarkdownLine { line, _, _ in
            MarkdownBridge.toggleTaskMarker(in: line)
        }
    }

    /// Mark caret task done (`[x]`) — vim `md`.
    @discardableResult
    func markTaskDone() -> Bool {
        mutateCaretMarkdownLine { line, _, _ in
            MarkdownBridge.markTaskDone(in: line)
        }
    }

    /// Mark caret task open (`[ ]`) — vim `mD`.
    @discardableResult
    func markTaskOpen() -> Bool {
        mutateCaretMarkdownLine { line, _, _ in
            MarkdownBridge.markTaskOpen(in: line)
        }
    }

    /// Focus the caret’s open task (`[!]`), or clear focus if already focused (vim `mf` / Format menu).
    /// Enforces at most one focused task in the document.
    @discardableResult
    func toggleFocusTask() -> Bool {
        mutateCaretMarkdownLine { line, lines, lineIdx in
            guard let focused = MarkdownBridge.toggleFocusMarker(in: line) else { return nil }
            // Clear any other focused task so only one `[!]` remains.
            if MarkdownBridge.taskState(in: focused) == .focused {
                for i in lines.indices where i != lineIdx {
                    lines[i] = MarkdownBridge.clearFocusMarker(in: lines[i])
                }
            }
            return focused
        }
    }

    /// Shared path for caret-line markdown edits (task toggle / done / open / focus).
    @discardableResult
    private func mutateCaretMarkdownLine(
        _ transform: (_ line: String, _ lines: inout [String], _ lineIdx: Int) -> String?
    ) -> Bool {
        if let active = activeSourceLine {
            syncLineAtIndex(active)
        }

        let lineIdx = caretLineIndex()
        var lines = markdownLines
        while lines.count <= lineIdx {
            lines.append("")
        }

        let before = lines[lineIdx]
        guard let updated = transform(before, &lines, lineIdx) else { return false }
        let becameDone =
            MarkdownBridge.taskState(in: before) != .done
            && MarkdownBridge.taskState(in: updated) == .done

        lines[lineIdx] = updated
        MarkdownBridge.reconcileTaskTree(around: lineIdx, in: &lines)
        markdownSource = lines.joined(separator: "\n")

        let stayRaw = activeSourceLine == lineIdx
        if !stayRaw {
            activeSourceLine = nil
        }
        let caretCol: Int
        if stayRaw, let bracket = updated.firstIndex(of: "]") {
            var end = updated.distance(from: updated.startIndex, to: bracket) + 1
            let after = updated.index(after: bracket)
            if after < updated.endIndex, updated[after] == " " { end += 1 }
            caretCol = end
        } else {
            caretCol = 1
        }
        liveRestyle(
            to: MarkdownBridge.MarkdownCaret(line: lineIdx, column: caretCol),
            animateScroll: false
        )

        if becameDone {
            celebrateTaskCompleted(atLine: lineIdx)
        }
        delegate?.editorDidChangeText(self)
        return true
    }

    private func taskStateAtCaret() -> TaskMarkerState? {
        let lines = markdownLines
        let idx = caretLineIndex()
        guard idx >= 0, idx < lines.count else { return nil }
        return MarkdownBridge.taskState(in: lines[idx])
    }

    var canToggleTask: Bool {
        taskStateAtCaret() != nil
    }

    var canMarkTaskDone: Bool {
        guard let state = taskStateAtCaret() else { return false }
        return state != .done
    }

    var canMarkTaskOpen: Bool {
        guard let state = taskStateAtCaret() else { return false }
        return state != .open
    }

    var canToggleFocusTask: Bool {
        guard let state = taskStateAtCaret() else { return false }
        return state.isOpenLike
    }
    /// `o` / `O` — open a line below / above and enter Insert (continues list/task markers).
    func vimOpenLine(above: Bool) {
        hideVimChordHint()
        pendingVimKey = nil
        collapseSelectionToCaret()

        if let active = activeSourceLine {
            syncLineAtIndex(active)
        }

        let caret = currentMarkdownCaret()
        var lines = markdownLines
        while lines.count <= caret.line {
            lines.append("")
        }

        let prefix = MarkdownBridge.listContinuationPrefix(for: lines[caret.line])
        RoobytesDebugLog.event(
            "openLine above=\(above) caretLine=\(caret.line) prefix=\(prefix.debugDescription) lines=\(lines.count)→\(lines.count + 1)"
        )
        let newLineIdx: Int
        if above {
            lines.insert(prefix, at: caret.line)
            newLineIdx = caret.line
        } else {
            lines.insert(prefix, at: caret.line + 1)
            newLineIdx = caret.line + 1
        }
        shiftFoldsForInsert(count: 1, at: newLineIdx)
        if MarkdownBridge.taskState(in: lines[newLineIdx]) != nil {
            MarkdownBridge.reconcileTaskTree(around: newLineIdx, in: &lines)
        }
        markdownSource = lines.joined(separator: "\n")

        vimMode = .insert
        visualModeBadge.hide()
        let col = (prefix as NSString).length
        let target = MarkdownBridge.MarkdownCaret(line: newLineIdx, column: col)

        activeSourceLine = newLineIdx
        liveRestyle(to: target, animateScroll: false)

        textView.updateInsertionPointStateAndRestartTimer(true)
        textView.setNeedsDisplay(textView.visibleRect)
        delegate?.editorDidChangeVimMode(self)
        delegate?.editorDidChangeText(self)
    }
    /// Vim `r` / `Nr` — replace character(s) under the caret; stay in Normal.
    func vimReplaceCharacter(_ replacement: Character, count: Int) {
        let n = max(1, count)
        syncMarkdownFromView()
        var caret = currentMarkdownCaret()
        var lines = markdownLines
        guard caret.line >= 0, caret.line < lines.count else {
            refreshBlockCaret()
            return
        }

        let line = lines[caret.line]
        guard let startIdx = stringIndex(in: line, atUTF16Column: caret.column),
              startIdx < line.endIndex
        else {
            refreshBlockCaret()
            return
        }

        var chars = Array(line)
        let charIndex = line.distance(from: line.startIndex, to: startIdx)
        var lastCharIndex = charIndex
        var replaced = 0
        for offset in 0..<n {
            let i = charIndex + offset
            guard i < chars.count else { break }
            if chars[i] == "\n" || chars[i] == "\r" { break }
            chars[i] = replacement
            lastCharIndex = i
            replaced += 1
        }
        guard replaced > 0 else {
            refreshBlockCaret()
            return
        }

        let newLine = String(chars)
        lines[caret.line] = newLine
        markdownSource = lines.joined(separator: "\n")

        let lastIdx = newLine.index(newLine.startIndex, offsetBy: lastCharIndex)
        caret.column = newLine.utf16.distance(
            from: newLine.utf16.startIndex,
            to: lastIdx.samePosition(in: newLine.utf16) ?? newLine.utf16.endIndex
        )

        activeSourceLine = nil
        liveRestyle(to: caret, animateScroll: false)
        refreshBlockCaret()
        updateLineNumberGutter()
        delegate?.editorDidChangeText(self)
    }

    private func stringIndex(in string: String, atUTF16Column column: Int) -> String.Index? {
        let utf16 = string.utf16
        guard column >= 0, column < utf16.count else { return nil }
        let i = utf16.index(utf16.startIndex, offsetBy: column)
        return String.Index(i, within: string)
    }
    /// `yy` / `Nyy` — copy Roobytes-flavored line content (no markers / `tag:`) into yank buffer + pasteboard.
    func vimYankLinesContent(_ count: Int) {
        clearVimPrefix()
        syncMarkdownFromView()
        let lines = markdownLines
        let start = caretLineIndex()
        guard !lines.isEmpty, start >= 0, start < lines.count else {
            refreshBlockCaret()
            return
        }
        let end = min(lines.count, start + max(1, count))
        let yanked = Array(lines[start..<end])
            .map { MarkdownBridge.yankableContent(of: $0) }
            .joined(separator: "\n")
        storeVimYank(yanked, kind: .linewise, pasteboardTrailingNewline: false)
        refreshBlockCaret()
    }

    /// `dd` / `Ndd` — cut lines into the linewise yank buffer (+ pasteboard).
    func vimDeleteLines(_ count: Int) {
        syncMarkdownFromView()
        var lines = markdownLines
        let start = caretLineIndex()
        guard !lines.isEmpty, start >= 0, start < lines.count else {
            refreshBlockCaret()
            return
        }
        let end = min(lines.count, start + max(1, count))
        let yanked = Array(lines[start..<end]).joined(separator: "\n")
        storeVimYank(yanked, kind: .linewise, pasteboardTrailingNewline: true)

        shiftFoldsForDelete(start..<end)
        lines.removeSubrange(start..<end)
        if lines.isEmpty { lines = [""] }
        markdownSource = lines.joined(separator: "\n")

        let newLine = min(start, lines.count - 1)
        activeSourceLine = nil
        let caret = MarkdownBridge.MarkdownCaret(line: newLine, column: 0)
        liveRestyle(to: caret, animateScroll: false)
        refreshBlockCaret()
        updateLineNumberGutter()
        delegate?.editorDidChangeText(self)
    }

    /// Visual `y` — characterwise yank of the selection; leave Visual at the selection start.
    func vimYankVisualSelection() {
        clearVimPrefix()
        guard vimMode == .visual,
              let endpoints = visualMarkdownEndpoints()
        else {
            leaveVisualMode()
            return
        }
        syncMarkdownFromView()
        let yanked = VimCharacterwise.slice(
            from: endpoints.lo,
            through: endpoints.hi,
            in: markdownLines
        )
        storeVimYank(yanked, kind: .characterwise, pasteboardTrailingNewline: false)
        leaveVisualMode(at: endpoints.lo)
    }

    /// Visual `d` / `x` — characterwise cut of the selection; leave Visual at the deletion start.
    func vimDeleteVisualSelection() {
        clearVimPrefix()
        guard vimMode == .visual,
              let endpoints = visualMarkdownEndpoints()
        else {
            leaveVisualMode()
            return
        }
        syncMarkdownFromView()
        let lines = markdownLines
        let yanked = VimCharacterwise.slice(
            from: endpoints.lo,
            through: endpoints.hi,
            in: lines
        )
        storeVimYank(yanked, kind: .characterwise, pasteboardTrailingNewline: false)

        if let removed = VimCharacterwise.deletedLineRange(from: endpoints.lo, through: endpoints.hi) {
            shiftFoldsForDelete(removed)
        }
        let result = VimCharacterwise.deleting(
            from: endpoints.lo,
            through: endpoints.hi,
            in: lines
        )
        markdownSource = result.lines.joined(separator: "\n")
        leaveVisualMode(at: result.caret)
        updateLineNumberGutter()
        delegate?.editorDidChangeText(self)
    }

    /// Put — linewise (`dd`/`yy`) or characterwise (Visual `y`/`d`).
    /// Linewise: `p` below caret line, `P` above. Characterwise: `p` after caret char, `P` before.
    func vimPut(after: Bool) {
        clearVimPrefix()
        guard let yanked = vimYankLines, !yanked.isEmpty else {
            refreshBlockCaret()
            return
        }
        if vimYankKind == .characterwise {
            vimPutCharacterwise(yanked, after: after)
            return
        }
        syncMarkdownFromView()
        var lines = markdownLines
        let insertLines = yanked.components(separatedBy: "\n")
        let current = caretLineIndex()
        let idx: Int
        if after {
            idx = min(lines.count, current + 1)
        } else {
            idx = max(0, current)
        }
        shiftFoldsForInsert(count: insertLines.count, at: idx)
        lines.insert(contentsOf: insertLines, at: idx)
        markdownSource = lines.joined(separator: "\n")

        activeSourceLine = nil
        let caret = MarkdownBridge.MarkdownCaret(line: idx, column: 0)
        liveRestyle(to: caret, animateScroll: false)
        refreshBlockCaret()
        updateLineNumberGutter()
        delegate?.editorDidChangeText(self)
    }

    private func vimPutCharacterwise(_ yanked: String, after: Bool) {
        syncMarkdownFromView()
        var caret = currentMarkdownCaret()
        let lines = markdownLines
        guard caret.line >= 0, caret.line < lines.count else {
            refreshBlockCaret()
            return
        }
        if after {
            let ns = lines[caret.line] as NSString
            if caret.column < ns.length {
                caret.column += 1
            }
        }
        let pieces = yanked.components(separatedBy: "\n")
        if pieces.count > 1 {
            shiftFoldsForInsert(count: pieces.count - 1, at: caret.line + 1)
        }
        let result = VimCharacterwise.inserting(yanked, at: caret, in: lines)
        markdownSource = result.lines.joined(separator: "\n")
        activeSourceLine = nil
        liveRestyle(to: result.caret, animateScroll: false)
        refreshBlockCaret()
        updateLineNumberGutter()
        delegate?.editorDidChangeText(self)
    }

    private func storeVimYank(
        _ text: String,
        kind: VimYankKind,
        pasteboardTrailingNewline: Bool
    ) {
        vimYankLines = text
        vimYankKind = kind
        let pb = NSPasteboard.general
        pb.clearContents()
        let paste = pasteboardTrailingNewline ? text + "\n" : text
        pb.setString(paste, forType: .string)
    }

    private func visualMarkdownEndpoints() -> (
        lo: MarkdownBridge.MarkdownCaret,
        hi: MarkdownBridge.MarkdownCaret
    )? {
        guard let storage = textView.textStorage,
              let anchor = visualAnchor,
              let caret = visualCaret
        else { return nil }
        let a = MarkdownBridge.markdownCaret(
            attributedLocation: anchor,
            attributed: storage,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines
        )
        let b = MarkdownBridge.markdownCaret(
            attributedLocation: caret,
            attributed: storage,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines
        )
        return VimCharacterwise.ordered(a, b)
    }

    // MARK: - Nested list folds (`za` / `zc` / `zo`)

    func clearListFolds() {
        foldedParentLines = []
    }

    /// Keep session folds across line insert/delete by shifting parent indices.
    func shiftFoldsForInsert(count: Int, at index: Int) {
        foldedParentLines = MarkdownBridge.foldsAfterInserting(
            count: count,
            at: index,
            into: foldedParentLines
        )
    }

    private func shiftFoldsForDelete(_ range: Range<Int>) {
        foldedParentLines = MarkdownBridge.foldsAfterDeleting(range, from: foldedParentLines)
    }

    /// Unfold any folded parent that contains `line` (or is `line`) before Insert reveals raw text.
    func autoUnfoldForInsert(around line: Int) {
        guard !foldedParentLines.isEmpty else { return }
        let lines = markdownLines
        foldedParentLines = foldedParentLines.filter { parent in
            guard MarkdownBridge.canFold(parent: parent, in: lines) else { return false }
            if parent == line { return false }
            if let range = MarkdownBridge.childLineRange(parent: parent, in: lines), range.contains(line) {
                return false
            }
            return true
        }
    }

    /// Drop fold marks that no longer point at a foldable parent (stale after edits).
    func pruneInvalidFolds() {
        guard !foldedParentLines.isEmpty else { return }
        let lines = markdownLines
        let before = foldedParentLines
        foldedParentLines = before.filter { MarkdownBridge.canFold(parent: $0, in: lines) }
        if foldedParentLines != before {
            RoobytesDebugLog.event("folds pruned \(before.count)→\(foldedParentLines.count)")
        }
    }

    func vimFoldToggle() {
        let line = caretLineIndex()
        let lines = markdownLines
        guard MarkdownBridge.canFold(parent: line, in: lines) else {
            refreshBlockCaret()
            return
        }
        if foldedParentLines.contains(line) {
            foldedParentLines.remove(line)
        } else {
            foldedParentLines.insert(line)
        }
        liveRestyle(to: currentMarkdownCaret(), animateScroll: false)
        refreshBlockCaret()
    }

    func vimFoldClose() {
        let line = caretLineIndex()
        let lines = markdownLines
        guard MarkdownBridge.canFold(parent: line, in: lines) else {
            refreshBlockCaret()
            return
        }
        guard !foldedParentLines.contains(line) else {
            refreshBlockCaret()
            return
        }
        foldedParentLines.insert(line)
        liveRestyle(to: currentMarkdownCaret(), animateScroll: false)
        refreshBlockCaret()
    }

    func vimFoldOpen() {
        let line = caretLineIndex()
        guard foldedParentLines.contains(line) else {
            refreshBlockCaret()
            return
        }
        foldedParentLines.remove(line)
        liveRestyle(to: currentMarkdownCaret(), animateScroll: false)
        refreshBlockCaret()
    }

    /// Fold every done (`[x]`) task that still has nested children (`:folddone` / `:fd`).
    @discardableResult
    func foldAllDoneTasks() -> Int {
        let lines = markdownLines
        let parents = MarkdownBridge.foldableDoneTaskParents(in: lines)
        guard !parents.isEmpty else { return 0 }
        let before = foldedParentLines.count
        foldedParentLines.formUnion(parents)
        if foldedParentLines.count != before {
            liveRestyle(to: currentMarkdownCaret(), animateScroll: false)
            refreshBlockCaret()
        }
        return parents.count
    }
}

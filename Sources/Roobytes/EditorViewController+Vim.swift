import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    // MARK: - Vim (simple Normal / Insert)
    /// - Returns: `true` if the event was handled (do not pass to NSTextView).
    func handleVimKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Command-line mode (`:…`) takes over typing until Esc / Enter.
        if vimCommandLine != nil {
            return handleVimCommandLineKey(event)
        }

        // `:h` / tip panel — Esc / q dismiss; help also scrolls with Normal ⌃e/y/d/u.
        if isVimHelpVisible || isTipVisible {
            if Self.isEscapeEvent(event) {
                RoobytesDebugLog.event(isTipVisible ? "tip dismiss Esc" : "help dismiss Esc")
                hideVimHelp()
                hideTip()
                return true
            }
            if !mods.contains(.command), !mods.contains(.control), !mods.contains(.option),
               event.charactersIgnoringModifiers == "q"
            {
                RoobytesDebugLog.event(isTipVisible ? "tip dismiss q" : "help dismiss q")
                hideVimHelp()
                hideTip()
                return true
            }
            if isVimHelpVisible,
               mods.contains(.control), !mods.contains(.command), !mods.contains(.option),
               let ch = event.charactersIgnoringModifiers?.lowercased().first
            {
                switch ch {
                case "e":
                    commandPalette.scrollContentLines(1)
                    return true
                case "y":
                    commandPalette.scrollContentLines(-1)
                    return true
                case "d":
                    commandPalette.scrollContentHalfPages(1)
                    return true
                case "u":
                    commandPalette.scrollContentHalfPages(-1)
                    return true
                default:
                    break
                }
            }
            RoobytesDebugLog.event("overlay ignore key=\(Self.debugKeyDescription(event))")
            return true
        }

        // Escape first — before Control/Option early-outs. Spurious modifier bits on Esc
        // used to fall through; AppKit `^o` is insertNewlineIgnoringFieldEditor (opens a line).
        if Self.isEscapeEvent(event) {
            let modeLabel: String
            switch vimMode {
            case .normal: modeLabel = "normal"
            case .insert: modeLabel = "insert"
            case .visual: modeLabel = "visual"
            }
            RoobytesDebugLog.event("Esc mode=\(modeLabel)")
            handleVimEscape()
            return true
        }

        // Insert word completion navigation / accept (before falling through to AppKit).
        if vimMode == .insert, wordCompletion.isVisible,
           !mods.contains(.command), !mods.contains(.control), !mods.contains(.option)
        {
            switch event.keyCode {
            case 125: // down
                wordCompletion.moveSelection(1)
                if let anchors = wordCompletionAnchorsForCurrentPrefix() {
                    wordCompletion.updateGhost(originInHost: anchors.ghost)
                }
                return true
            case 126: // up
                wordCompletion.moveSelection(-1)
                if let anchors = wordCompletionAnchorsForCurrentPrefix() {
                    wordCompletion.updateGhost(originInHost: anchors.ghost)
                }
                return true
            case 48: // Tab
                acceptWordCompletion()
                return true
            case 36, 76: // Return / keypad Enter
                acceptWordCompletion()
                return true
            default:
                break
            }
        }

        // Ctrl-E/Y line · Ctrl-D/U half-page — scroll without moving the caret (Normal / Visual).
        if mods.contains(.control), !mods.contains(.command), !mods.contains(.option) {
            if (vimMode == .normal || vimMode == .visual),
               let ch = event.charactersIgnoringModifiers?.lowercased().first
            {
                switch ch {
                case "e":
                    clearVimPrefix()
                    vimScrollLines(1)
                    return true
                case "y":
                    clearVimPrefix()
                    vimScrollLines(-1)
                    return true
                case "d":
                    vimScrollHalfPages(takeVimCount())
                    return true
                case "u":
                    vimScrollHalfPages(-takeVimCount())
                    return true
                default:
                    break
                }
            }
            // Block control keys that produce newlines: ^O (open line), ^J (LF), ^M (CR).
            // Consume so Insert never “opens a line” via Control-O.
            if let ch = event.charactersIgnoringModifiers?.lowercased().first,
               ch == "o" || ch == "j" || ch == "m"
            {
                clearVimPrefix()
                return true
            }
            clearVimPrefix()
            return false
        }

        // Leave menu shortcuts alone (⌘↩ toggle task, ⌘B, etc.).
        if mods.contains(.command) || mods.contains(.option) {
            clearVimPrefix()
            return false
        }

        guard vimMode == .normal || vimMode == .visual else { return false }

        // Arrow keys — own the move in Normal / Visual. A length-1 block selection makes
        // AppKit `moveLeft:` collapse in place (first press looks broken); `h`/`l`
        // already work via vimMoveHorizontal.
        if Self.isNavigationKeyCode(event.keyCode) {
            let displayRows = VimVerticalMotion.usesDisplayRows(hasCount: vimCount > 0, gPrefixed: false)
            let count = takeVimCount()
            switch event.keyCode {
            case 123: // left
                vimMoveHorizontal(-count)
                return true
            case 124: // right
                vimMoveHorizontal(count)
                return true
            case 125: // down
                vimMoveVertical(count, byDisplayRow: displayRows)
                return true
            case 126: // up
                vimMoveVertical(-count, byDisplayRow: displayRows)
                return true
            default:
                // home / end / page — still let the text view handle these
                clearVimPrefix()
                return false
            }
        }

        guard let chars = event.characters, chars.count == 1, let ch = chars.first else {
            clearVimPrefix()
            return true
        }

        // Visual: motions + yank/cut + Esc. Insert entry / other operators are swallowed.
        if vimMode == .visual {
            return handleVimVisualKey(ch)
        }

        if let pending = pendingVimKey {
            hideVimChordHint()
            pendingVimKey = nil
            if pending == "z", ch == "=" {
                clearVimPrefix()
                vimAutoFixSpellingUnderCaret()
                return true
            }
            if pending == "z", ch == "z" {
                clearVimPrefix()
                vimCenterCursorLine()
                return true
            }
            if pending == "z", ch == "a" {
                clearVimPrefix()
                vimFoldToggle()
                return true
            }
            if pending == "z", ch == "c" {
                clearVimPrefix()
                vimFoldClose()
                return true
            }
            if pending == "z", ch == "o" {
                clearVimPrefix()
                vimFoldOpen()
                return true
            }
            if pending == "g", ch == "g" {
                clearVimPrefix()
                vimGoToDocumentEdge(top: true)
                return true
            }
            if pending == "g", ch == "j" {
                vimMoveVertical(takeVimCount(), byDisplayRow: true)
                return true
            }
            if pending == "g", ch == "k" {
                vimMoveVertical(-takeVimCount(), byDisplayRow: true)
                return true
            }
            if pending == "g", ch == "x" {
                clearVimPrefix()
                vimOpenURLUnderCaret(privateBrowsing: false)
                return true
            }
            if pending == "g", ch == "X" {
                clearVimPrefix()
                vimOpenURLUnderCaret(privateBrowsing: true)
                return true
            }
            if pending == "m", ch == "f" {
                clearVimPrefix()
                _ = toggleFocusTask()
                return true
            }
            if pending == "m", ch == "d" {
                clearVimPrefix()
                if !markTaskDone() {
                    NSSound.beep()
                }
                return true
            }
            if pending == "m", ch == "D" {
                clearVimPrefix()
                if !markTaskOpen() {
                    NSSound.beep()
                }
                return true
            }
            if pending == "'", ch == "f" {
                clearVimPrefix()
                vimGoToFocusedTask()
                return true
            }
            if pending == "]", ch == "t" {
                vimJumpUndoneTask(forward: true, count: takeVimCount())
                return true
            }
            if pending == "[", ch == "t" {
                vimJumpUndoneTask(forward: false, count: takeVimCount())
                return true
            }
            if pending == "d", ch == "d" {
                vimDeleteLines(takeVimCount())
                return true
            }
            if pending == "y", ch == "y" {
                vimYankLinesContent(takeVimCount())
                return true
            }
            if pending == "r" {
                // `rX` / `3rX` — replace under (and following) caret; digits are the replacement.
                let count = vimCount > 0 ? vimCount : 1
                vimCount = 0
                if ch.isNewline || ch == "\r" || ch == "\t" {
                    return true
                }
                vimReplaceCharacter(ch, count: count)
                return true
            }
            // Unknown second key — drop count and fall through.
            vimCount = 0
        }

        // Count prefix: `5j`, `3dd` (digits only; bare `0` is line-start motion).
        if let digit = ch.wholeNumberValue, (digit > 0 || vimCount > 0) {
            hideVimChordHint()
            pendingVimKey = nil
            vimCount = min(vimCount * 10 + digit, 9999)
            return true
        }

        switch ch {
        case "0":
            clearVimPrefix()
            vimMoveToLineStart()
            return true
        case "$":
            clearVimPrefix()
            vimMoveToLineEnd()
            return true
        case ":":
            clearVimPrefix()
            beginVimCommandLine()
            return true
        case "i":
            clearVimPrefix()
            enterInsert(placement: .beforeCaret)
            return true
        case "a":
            clearVimPrefix()
            enterInsert(placement: .afterCaret)
            return true
        case "I":
            clearVimPrefix()
            enterInsert(placement: .lineStart)
            return true
        case "A":
            clearVimPrefix()
            enterInsert(placement: .lineEnd)
            return true
        case "o":
            clearVimPrefix()
            RoobytesDebugLog.event("vim o openLine below")
            vimOpenLine(above: false)
            return true
        case "O":
            clearVimPrefix()
            RoobytesDebugLog.event("vim O openLine above")
            vimOpenLine(above: true)
            return true
        case "h":
            vimMoveHorizontal(-takeVimCount())
            return true
        case "l":
            vimMoveHorizontal(takeVimCount())
            return true
        case "j":
            let downByRow = VimVerticalMotion.usesDisplayRows(hasCount: vimCount > 0, gPrefixed: false)
            vimMoveVertical(takeVimCount(), byDisplayRow: downByRow)
            return true
        case "k":
            let upByRow = VimVerticalMotion.usesDisplayRows(hasCount: vimCount > 0, gPrefixed: false)
            vimMoveVertical(-takeVimCount(), byDisplayRow: upByRow)
            return true
        case "K":
            clearVimPrefix()
            vimLookupWordUnderCaret()
            return true
        case "w":
            vimMoveWord(.forwardStart, count: takeVimCount())
            return true
        case "b":
            vimMoveWord(.backwardStart, count: takeVimCount())
            return true
        case "e":
            vimMoveWord(.forwardEnd, count: takeVimCount())
            return true
        case "d":
            // Wait for second `d` (`dd` / `3dd`). Keep vimCount.
            setPendingVimKey("d")
            return true
        case "y":
            // Wait for second `y` (`yy` / `3yy`). Keep vimCount.
            setPendingVimKey("y")
            return true
        case "r":
            // Wait for replacement char (`rX` / `3rX`). Keep vimCount.
            setPendingVimKey("r")
            return true
        case "p":
            vimPut(after: true)
            return true
        case "P":
            vimPut(after: false)
            return true
        case "u":
            vimUndo(times: takeVimCount())
            return true
        case "v":
            clearVimPrefix()
            enterVisualMode()
            return true
        case "G":
            clearVimPrefix()
            vimGoToDocumentEdge(top: false)
            return true
        case "g":
            setPendingVimKey("g")
            return true
        case "z":
            setPendingVimKey("z")
            return true
        case "m":
            // Wait for mark id (`mf` / `md` / `mD`).
            setPendingVimKey("m")
            return true
        case "'":
            // Wait for mark id (`'f` = jump to focus task).
            setPendingVimKey("'")
            return true
        case "]":
            // Wait for second key (`]t` next undone task). Keep vimCount.
            setPendingVimKey("]")
            return true
        case "[":
            // Wait for second key (`[t` previous undone task). Keep vimCount.
            setPendingVimKey("[")
            return true
        default:
            clearVimPrefix()
            return true
        }
    }
    /// Characterwise Visual key handling — motions extend selection; `y`/`d`/`x` operate; `v` / Esc leave.
    private func handleVimVisualKey(_ ch: Character) -> Bool {
        if let pending = pendingVimKey {
            hideVimChordHint()
            pendingVimKey = nil
            if pending == "g", ch == "g" {
                clearVimPrefix()
                vimGoToDocumentEdge(top: true)
                return true
            }
            if pending == "g", ch == "j" {
                vimMoveVertical(takeVimCount(), byDisplayRow: true)
                return true
            }
            if pending == "g", ch == "k" {
                vimMoveVertical(-takeVimCount(), byDisplayRow: true)
                return true
            }
            // Unknown second key — drop pending and fall through.
            vimCount = 0
        }

        // Count prefix: `5j`, `3w`.
        if let digit = ch.wholeNumberValue, (digit > 0 || vimCount > 0) {
            vimCount = min(vimCount * 10 + digit, 9999)
            return true
        }

        switch ch {
        case "v":
            // Toggle off (vim).
            leaveVisualMode()
            return true
        case "y":
            vimYankVisualSelection()
            return true
        case "d", "x":
            vimDeleteVisualSelection()
            return true
        case "0":
            clearVimPrefix()
            vimMoveToLineStart()
            return true
        case "$":
            clearVimPrefix()
            vimMoveToLineEnd()
            return true
        case "h":
            vimMoveHorizontal(-takeVimCount())
            return true
        case "l":
            vimMoveHorizontal(takeVimCount())
            return true
        case "j":
            let downByRow = VimVerticalMotion.usesDisplayRows(hasCount: vimCount > 0, gPrefixed: false)
            vimMoveVertical(takeVimCount(), byDisplayRow: downByRow)
            return true
        case "k":
            let upByRow = VimVerticalMotion.usesDisplayRows(hasCount: vimCount > 0, gPrefixed: false)
            vimMoveVertical(-takeVimCount(), byDisplayRow: upByRow)
            return true
        case "w":
            vimMoveWord(.forwardStart, count: takeVimCount())
            return true
        case "b":
            vimMoveWord(.backwardStart, count: takeVimCount())
            return true
        case "e":
            vimMoveWord(.forwardEnd, count: takeVimCount())
            return true
        case "g":
            setPendingVimKey("g")
            return true
        case "G":
            clearVimPrefix()
            vimGoToDocumentEdge(top: false)
            return true
        default:
            clearVimPrefix()
            return true
        }
    }

    func enterVisualMode() {
        endVimCommandLine()
        hideWordCompletion()
        clearVimPrefix()
        let loc = textView.selectedRange().location
        visualAnchor = loc
        visualCaret = loc
        let changing = vimMode != .visual
        vimMode = .visual
        visualModeBadge.show()
        applyVisualSelection()
        textView.updateInsertionPointStateAndRestartTimer(true)
        textView.setNeedsDisplay(textView.visibleRect)
        if changing {
            delegate?.editorDidChangeVimMode(self)
        }
    }

    /// Leave Visual. When `markdownCaret` is set, land there; pass `restyle: false` for
    /// no-op content changes (Visual `y`) to skip a full Live Preview rebuild.
    func leaveVisualMode(
        at markdownCaret: MarkdownBridge.MarkdownCaret? = nil,
        restyle: Bool = true
    ) {
        let movingEnd = visualCaret ?? textView.selectedRange().location
        visualAnchor = nil
        visualCaret = nil
        if let markdownCaret {
            endVimCommandLine()
            hideWordCompletion()
            clearVimPrefix()
            clearCaretFeedback()
            let changing = vimMode != .normal
            vimMode = .normal
            visualModeBadge.hide()
            activeSourceLine = nil
            if restyle {
                liveRestyle(to: markdownCaret, animateScroll: false)
            } else {
                landNormalCaret(at: markdownCaret)
            }
            refreshBlockCaret()
            textView.updateInsertionPointStateAndRestartTimer(true)
            textView.setNeedsDisplay(textView.visibleRect)
            if changing {
                delegate?.editorDidChangeVimMode(self)
            }
            return
        }
        isUpdatingBlockCaret = true
        textView.setSelectedRange(NSRange(location: movingEnd, length: 0))
        isUpdatingBlockCaret = false
        setVimMode(.normal)
    }

    /// Place the Normal block caret at `markdownCaret` without rebuilding attributed text.
    private func landNormalCaret(at markdownCaret: MarkdownBridge.MarkdownCaret) {
        guard let storage = textView.textStorage else { return }
        refreshSourceLineParagraphIndexIfNeeded()
        let loc = MarkdownBridge.attributedLocation(
            for: markdownCaret,
            attributed: storage,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        isUpdatingBlockCaret = true
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        isUpdatingBlockCaret = false
    }

    func applyVisualSelection() {
        guard vimMode == .visual,
              let anchor = visualAnchor,
              let caret = visualCaret
        else { return }
        let len = (textView.string as NSString).length
        let range = VimVisual.selectionRange(anchor: anchor, caret: caret, documentLength: len)
        isUpdatingBlockCaret = true
        textView.setSelectedRange(range)
        isUpdatingBlockCaret = false
    }

    private func setPendingVimKey(_ ch: Character) {
        pendingVimKey = ch
        if vimMode != .visual {
            collapseSelectionToCaret()
        }
        textView.updateInsertionPointStateAndRestartTimer(true)
        textView.setNeedsDisplay(textView.visibleRect)
        showVimChordHints(for: ch)
    }

    func clearVimPrefix() {
        let wasPending = pendingVimKey != nil
        pendingVimKey = nil
        vimCount = 0
        hideVimChordHint()
        if wasPending, vimMode == .normal {
            refreshBlockCaret()
        }
    }
    /// Esc / `\u{1b}` — leave Insert / Visual, discard IME marked text, cancel pending chords.
    @discardableResult
    func handleVimEscape() -> Bool {
        if isVimHelpVisible {
            hideVimHelp()
            return true
        }
        if isTipVisible {
            hideTip()
            return true
        }
        hideWordCompletion()
        if textView.hasMarkedText() {
            textView.inputContext?.discardMarkedText()
            textView.unmarkText()
        }
        clearVimPrefix()
        if vimCommandLine != nil {
            endVimCommandLine()
            return true
        }
        if vimMode == .visual {
            leaveVisualMode()
            return true
        }
        if vimMode == .insert {
            setVimMode(.normal)
        }
        return true
    }

    static func isEscapeEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { return true }
        if event.charactersIgnoringModifiers == "\u{1b}" { return true }
        if event.characters == "\u{1b}" { return true }
        return false
    }

    private static func debugKeyDescription(_ event: NSEvent) -> String {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = ["keyCode=\(event.keyCode)"]
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("opt") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }
        return parts.joined(separator: " ")
    }

    /// Consume the count prefix; minimum 1 (vim default).
    private func takeVimCount() -> Int {
        let n = vimCount > 0 ? vimCount : 1
        vimCount = 0
        pendingVimKey = nil
        hideVimChordHint()
        return n
    }
    enum VimInsertPlacement {
        case beforeCaret
        case afterCaret
        case lineStart
        case lineEnd
    }

    enum VimWordMotion {
        case forwardStart
        case backwardStart
        case forwardEnd
    }
    private func enterInsert(placement: VimInsertPlacement) {
        clearVimPrefix()
        collapseSelectionToCaret()

        // Target the caret in markdown space. Decorated preview columns (checkbox
        // attachment, stripped markers, kerned bullets) do not match raw UTF-16
        // columns — moving in the view first made `A` land mid-line after restyle.
        var caret = currentMarkdownCaret()
        let lines = markdownLines
        let mdLine = caret.line < lines.count ? lines[caret.line] : ""
        let mdLen = (mdLine as NSString).length

        switch placement {
        case .beforeCaret:
            break
        case .afterCaret:
            // `a` = after the glyph under the block caret in the *view*, then map.
            // (mdCol+1 breaks when `` `code` `` / emphasis markers are stripped.)
            if let storage = textView.textStorage {
                let ns = storage.string as NSString
                var probe = textView.selectedRange().location
                if probe < ns.length {
                    let ch = ns.character(at: probe)
                    if ch != 10, ch != 13 {
                        probe += 1
                    }
                }
                caret = MarkdownBridge.markdownCaret(
                    attributedLocation: probe,
                    attributed: storage,
                    markdown: markdownSource,
                    activeSourceLine: activeSourceLine,
                    markdownLines: lines
                )
            } else if caret.column < mdLen {
                caret.column += 1
            }
        case .lineStart:
            caret.column = MarkdownBridge.contentStartColumn(in: mdLine)
        case .lineEnd:
            caret.column = mdLen
        }

        enterInsert(at: caret)
    }

    /// Enter Insert and restyle so `caret` is the raw-line insertion point.
    private func enterInsert(at caret: MarkdownBridge.MarkdownCaret) {
        endVimCommandLine()
        let changing = vimMode != .insert
        vimMode = .insert
        visualModeBadge.hide()
        hideVimChordHint()
        pendingVimKey = nil
        autoUnfoldForInsert(around: caret.line)

        activeSourceLine = caret.line
        liveRestyle(to: caret, animateScroll: false)

        textView.updateInsertionPointStateAndRestartTimer(true)
        textView.setNeedsDisplay(textView.visibleRect)
        if changing {
            delegate?.editorDidChangeVimMode(self)
        }
    }
    /// Vim `I` — first non-blank on the line (UTF-16 column).
    static func firstNonBlankColumn(in line: String) -> Int {
        let ns = line as NSString
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c != 32 && c != 9 { break }
            i += 1
        }
        return i
    }
    func setVimMode(_ newMode: VimEditorMode) {
        endVimCommandLine()
        hideWordCompletion()
        guard vimMode != newMode else { return }
        clearVimPrefix()
        clearCaretFeedback()
        if newMode != .visual {
            visualAnchor = nil
            visualCaret = nil
        }
        vimMode = newMode
        if newMode == .visual {
            visualModeBadge.show()
        } else {
            visualModeBadge.hide()
        }

        if newMode == .normal {
            let previous = activeSourceLine
            if let active = previous {
                let lineBefore = markdownLines.indices.contains(active) ? markdownLines[active] : "<OOB>"
                syncLineAtIndex(active)
                let lineAfter = markdownLines.indices.contains(active) ? markdownLines[active] : "<OOB>"
                if lineBefore != lineAfter {
                    RoobytesDebugLog.event("Esc sync[\(active)] before=\(lineBefore.prefix(50).debugDescription) after=\(lineAfter.prefix(50).debugDescription)")
                }
            }
            // Nested open task typed in Insert (or indent under a done parent) should
            // reopen ancestors — same rule as Enter / `o` creating `+ [ ]`.
            let syncedLine = activeSourceLine ?? previous
            if let synced = syncedLine, markdownLines.indices.contains(synced) {
                var lines = markdownLines
                if MarkdownBridge.taskState(in: lines[synced]) != nil {
                    let modified = MarkdownBridge.reconcileTaskTree(around: synced, in: &lines)
                    if !modified.isEmpty {
                        markdownSource = lines.joined(separator: "\n")
                    }
                }
            }
            // Backspace-join may move `activeSourceLine` to the previous line during sync.
            let caret = currentMarkdownCaret()
            activeSourceLine = nil
            collapseSelectionToCaret()
            // Always full-document restyle on Esc. Incremental replace indexes view
            // line ordinals; after a join the view/markdown layouts have diverged.
            liveRestyle(to: caret, animateScroll: false)
            refreshBlockCaret()
        } else if newMode == .insert {
            // Insert: reveal the caret line as raw markdown (Live Preview edit).
            collapseSelectionToCaret()
            let caret = currentMarkdownCaret()
            autoUnfoldForInsert(around: caret.line)
            let previous = activeSourceLine
            activeSourceLine = caret.line
            liveRestyle(
                to: caret,
                animateScroll: false,
                replacingOnly: [previous, caret.line].compactMap { $0 }
            )
            textView.updateInsertionPointStateAndRestartTimer(true)
        }
        // `.visual` is entered via `enterVisualMode()` (keeps selection state).

        textView.setNeedsDisplay(textView.visibleRect)
        delegate?.editorDidChangeVimMode(self)
    }
    private static func isNavigationKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 123, 124, 125, 126: // left right down up
            return true
        case 115, 119, 116, 121: // home end pageup pagedown
            return true
        default:
            return false
        }
    }
}

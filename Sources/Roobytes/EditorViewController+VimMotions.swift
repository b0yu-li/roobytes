import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    /// Ctrl-E (+1) / Ctrl-Y (−1) — scroll the viewport; caret stays put (classic vim).
    /// Instant steps so key-repeat feels snappy (animated scroll stacked badly when held).
    func vimScrollLines(_ delta: Int) {
        let clip = scrollView.contentView
        var step: CGFloat = 22
        let loc = textView.selectedRange().location
        let len = (textView.string as NSString).length
        if len > 0, let layoutManager = textView.layoutManager {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(loc, len - 1))
            let frag = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            if frag.height > 0 { step = frag.height }
        }
        // ~2 lines per tick — single presses still fine; hold-to-scroll keeps up with key repeat.
        let distance = step * 2
        scrollDocument(
            toY: clip.bounds.origin.y + CGFloat(delta) * distance,
            animated: false
        )
        TypewriterSound.shared.playMotion()
        if vimMode == .normal {
            textView.setNeedsDisplay(textView.visibleRect)
        }
    }

    /// Ctrl-D (+) / Ctrl-U (−) — half-page scroll; caret stays put (classic vim).
    func vimScrollHalfPages(_ delta: Int) {
        let clip = scrollView.contentView
        let half = max(clip.bounds.height * 0.5, 48)
        scrollDocument(
            toY: clip.bounds.origin.y + CGFloat(delta) * half,
            animated: false
        )
        TypewriterSound.shared.playMotion()
        if vimMode == .normal {
            textView.setNeedsDisplay(textView.visibleRect)
        }
    }
    func vimMoveToLineStart() {
        let ns = textView.string as NSString
        let loc = currentVimCaretLocation()
        var start = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
        vimMoveCaret(to: start)
    }

    func vimMoveToLineEnd() {
        let ns = textView.string as NSString
        let loc = currentVimCaretLocation()
        var start = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
        let target = contentsEnd > start ? contentsEnd - 1 : start
        vimMoveCaret(to: target)
    }

    func vimMoveHorizontal(_ delta: Int) {
        guard delta != 0 else {
            refreshBlockCaret()
            return
        }
        let ns = textView.string as NSString
        var loc = currentVimCaretLocation()
        let steps = abs(delta)
        let dir = delta > 0 ? 1 : -1

        for _ in 0..<steps {
            if dir < 0 {
                guard loc > 0 else { break }
                var start = 0, end = 0, contentsEnd = 0
                ns.getParagraphStart(
                    &start,
                    end: &end,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: loc, length: 0)
                )
                if loc == start { break }
                loc -= 1
            } else {
                guard loc < ns.length else { break }
                let ch = ns.character(at: loc)
                if ch == 10 || ch == 13 { break }
                loc += 1
            }
        }

        vimMoveCaret(to: loc)
    }

    /// `lineDelta` rows down (+) / up (−). Bare `j`/`k` pass `byDisplayRow` so wrapped
    /// paragraphs are walkable; counted moves stay logical (see `VimVerticalMotion`).
    func vimMoveVertical(_ lineDelta: Int, byDisplayRow: Bool = false) {
        guard lineDelta != 0 else {
            refreshBlockCaret()
            return
        }
        if byDisplayRow, vimMoveByDisplayRow(lineDelta) { return }
        vimMoveByLogicalLine(lineDelta)
    }

    /// Walk wrapped display rows, holding a sticky goal x. Returns `false` when there is
    /// no layout to measure, so the caller can fall back to logical lines.
    private func vimMoveByDisplayRow(_ delta: Int) -> Bool {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return false }
        let ns = textView.string as NSString
        let glyphCount = layoutManager.numberOfGlyphs
        guard ns.length > 0, glyphCount > 0 else { return false }

        let from = currentVimCaretLocation()
        // A trailing newline leaves an empty last line that owns no glyphs of its own.
        let startsOnExtraFragment = from >= ns.length
            && layoutManager.extraLineFragmentTextContainer != nil

        var fragmentGlyphs = NSRange(location: glyphCount, length: 0)
        var fragment = layoutManager.extraLineFragmentRect
        if !startsOnExtraFragment {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(from, ns.length - 1))
            fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentGlyphs)
        }

        let goalX = stickyGoalX(at: from) ?? caretX(
            at: from,
            in: fragment,
            layoutManager: layoutManager,
            ns: ns,
            onExtraFragment: startsOnExtraFragment
        )

        var moved = 0
        for _ in 0..<abs(delta) {
            if delta > 0 {
                let next = NSMaxRange(fragmentGlyphs)
                // Do not step onto AppKit's glyph-less `extraLineFragment` (trailing empty
                // after a final newline) — it has no gutter number and is not a real line.
                guard next < glyphCount else { break }
                fragment = layoutManager.lineFragmentRect(forGlyphAt: next, effectiveRange: &fragmentGlyphs)
            } else {
                let previous = fragmentGlyphs.location - 1
                guard previous >= 0 else { break }
                fragment = layoutManager.lineFragmentRect(forGlyphAt: previous, effectiveRange: &fragmentGlyphs)
            }
            moved += 1
        }

        guard moved > 0 else {
            rememberVerticalGoal(x: goalX, at: from)
            refreshBlockCaret()
            return true
        }

        var fraction: CGFloat = 0
        let target = layoutManager.characterIndex(
            for: NSPoint(x: goalX, y: fragment.midY),
            in: container,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        vimMoveCaret(to: target)
        rememberVerticalGoal(x: goalX, at: currentVimCaretLocation())
        return true
    }

    private func vimMoveByLogicalLine(_ lineDelta: Int) {
        let ns = textView.string as NSString
        let from = currentVimCaretLocation()
        rebuildLineIndexCache()
        let currentLine = lineIndexCache.lineIndex(at: from)
        let totalLines = lineIndexCache.lineCount
        let targetLine = max(0, min(totalLines - 1, currentLine + lineDelta))

        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        ns.getParagraphStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: from, length: 0)
        )
        // Sticky desired column — vim keeps it across short lines instead of truncating.
        let column = stickyGoalColumn(at: from) ?? max(0, from - lineStart)

        guard targetLine != currentLine else {
            rememberVerticalGoal(column: column, at: from)
            refreshBlockCaret()
            return
        }

        let targetStart = lineIndexCache.characterIndex(forLine: targetLine)
        var tEnd = 0, tContentsEnd = 0, tStart = 0
        ns.getParagraphStart(
            &tStart,
            end: &tEnd,
            contentsEnd: &tContentsEnd,
            for: NSRange(location: targetStart, length: 0)
        )
        let lineLen = max(0, tContentsEnd - tStart)
        let to = tStart + min(column, lineLen)

        vimMoveCaret(to: to)
        rememberVerticalGoal(column: column, at: currentVimCaretLocation())
    }

    /// Container-space x of the caret, used as the goal when starting a vertical run.
    private func caretX(
        at location: Int,
        in fragment: NSRect,
        layoutManager: NSLayoutManager,
        ns: NSString,
        onExtraFragment: Bool
    ) -> CGFloat {
        guard !onExtraFragment, ns.length > 0 else { return fragment.minX }
        if location >= ns.length {
            let glyph = layoutManager.glyphIndexForCharacter(at: ns.length - 1)
            return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).maxX
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        guard glyph < layoutManager.numberOfGlyphs else { return fragment.minX }
        return fragment.minX + layoutManager.location(forGlyphAt: glyph).x
    }

    private func stickyGoalX(at location: Int) -> CGFloat? {
        vimVerticalGoalAnchor == location ? vimVerticalGoalX : nil
    }

    private func stickyGoalColumn(at location: Int) -> Int? {
        vimVerticalGoalAnchor == location ? vimVerticalGoalColumn : nil
    }

    private func rememberVerticalGoal(x: CGFloat, at location: Int) {
        vimVerticalGoalX = x
        vimVerticalGoalColumn = nil
        vimVerticalGoalAnchor = location
    }

    private func rememberVerticalGoal(column: Int, at location: Int) {
        vimVerticalGoalColumn = column
        vimVerticalGoalX = nil
        vimVerticalGoalAnchor = location
    }

    /// Start UTF-16 index of 0-based line in `ns`.
    func characterIndex(forLine line: Int, in ns: NSString) -> Int {
        lineIndexCache.rebuildForced(from: ns, revision: viewTextRevision)
        return lineIndexCache.characterIndex(forLine: line)
    }
    func vimMoveWord(_ motion: VimWordMotion, count: Int = 1) {
        let ns = textView.string as NSString
        var loc = currentVimCaretLocation()
        let steps = max(1, count)
        for _ in 0..<steps {
            let next: Int
            switch motion {
            case .forwardStart:
                next = Self.wordMotionForwardStart(in: ns, from: loc)
            case .backwardStart:
                next = Self.wordMotionBackwardStart(in: ns, from: loc)
            case .forwardEnd:
                next = Self.wordMotionForwardEnd(in: ns, from: loc)
            }
            if next == loc { break }
            loc = next
        }
        vimMoveCaret(to: loc)
    }

    /// Active caret location — Visual uses the moving end, not `selectedRange.location`.
    func currentVimCaretLocation() -> Int {
        if vimMode == .visual, let caret = visualCaret {
            return caret
        }
        return textView.selectedRange().location
    }

    private func vimMoveCaret(to location: Int) {
        let from = currentVimCaretLocation()
        let nsLen = (textView.string as NSString).length
        var to = max(0, min(location, nsLen))
        // Normal: never rest on the glyph-less trailing empty line after a final `\n`.
        if vimMode == .normal, let storage = textView.textStorage {
            to = MarkdownBridge.caretLocationClampedOffTrailingEmpty(
                caretLocation: to,
                in: storage
            )
        }
        guard to != from else {
            if vimMode == .visual {
                applyVisualSelection()
            } else {
                refreshBlockCaret()
            }
            updateLineNumberGutter()
            return
        }

        let lineChanged = paragraphStart(at: from) != paragraphStart(at: to)
        let glyphDistance = abs(to - from)
        // Gate: skip micro `h`/`l` steps; keep signal for real jumps.
        let showGhost = glyphDistance >= 2 || lineChanged
        let showPulse = lineChanged

        if showGhost, let originRect = blockCaretRect(atCharacter: from) {
            playCaretOriginGhost(at: originRect)
        } else {
            clearCaretGhost()
        }

        if vimMode == .visual {
            visualCaret = to
            applyVisualSelection()
        } else {
            isUpdatingBlockCaret = true
            textView.setSelectedRange(NSRange(location: to, length: 0))
            isUpdatingBlockCaret = false
            refreshBlockCaret()
        }
        ensureVimCaretVisible(animated: false)
        updateLineNumberGutter()

        if showPulse, let destRect = blockCaretRect(atCharacter: to) {
            playCaretDestinationPulse(at: destRect)
        } else {
            clearCaretPulse()
        }
        TypewriterSound.shared.playMotion()
    }

    private func paragraphStart(at location: Int) -> Int {
        let ns = textView.string as NSString
        let loc = max(0, min(location, ns.length))
        var start = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
        return start
    }
    private func blockCaretRect(atCharacter location: Int) -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return nil }
        let ns = textView.string as NSString
        let len = ns.length
        guard len > 0 else { return nil }
        let loc = max(0, min(location, len - 1))
        let glyphRange: NSRange
        if loc < len, ns.character(at: loc) != 10, ns.character(at: loc) != 13 {
            glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: loc, length: 1),
                actualCharacterRange: nil
            )
        } else {
            glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: loc, length: 0),
                actualCharacterRange: nil
            )
        }
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        if rect.width < 4 {
            let font = textView.typingAttributes[.font] as? NSFont ?? RoobytesFont.regular(size: 13)
            rect.size.width = max(("M" as NSString).size(withAttributes: [.font: font]).width, 6)
        }
        return rect
    }

    /// Keep the caret on-screen (instant).
    private func ensureVimCaretVisible(animated: Bool) {
        _ = animated
        let loc = textView.selectedRange().location
        guard !isCharacterVisible(loc, padding: 28) else { return }
        scrollCharacterIntoViewInstant(loc, padding: 40)
    }

    func vimCenterCursorLine() {
        let loc = textView.selectedRange().location
        guard let lineY = lineFragmentOriginY(atCharacter: loc) else { return }
        let visibleH = scrollView.contentView.bounds.height
        var lineH: CGFloat = 18
        if let layoutManager = textView.layoutManager {
            let len = (textView.string as NSString).length
            let glyphIndex = len == 0 ? 0 : layoutManager.glyphIndexForCharacter(at: min(loc, len - 1))
            let frag = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            if frag.height > 0 { lineH = frag.height }
        }
        let targetY = lineY - (visibleH - lineH) / 2
        scrollDocument(toY: targetY, animated: false)
    }

    /// `gg` → first line · `G` → last line (preview Normal mode).
    func vimGoToDocumentEdge(top: Bool) {
        let lines = markdownLines
        guard !lines.isEmpty else { return }
        refreshSourceLineParagraphIndexIfNeeded()

        let attributed: NSAttributedString
        if let storage = textView.textStorage {
            attributed = storage
        } else {
            attributed = NSAttributedString(string: textView.string)
        }

        let lineIdx = top
            ? 0
            : MarkdownBridge.lastNavigableMarkdownLineIndex(in: lines, attributed: attributed)
        let col = Self.firstNonBlankColumn(in: lines[lineIdx])
        let target = MarkdownBridge.MarkdownCaret(line: lineIdx, column: col)
        let loc = MarkdownBridge.attributedLocation(
            for: target,
            attributed: attributed,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: lines,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        vimMoveCaret(to: loc)
    }
    private static let vimWordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    private static func isWordChar(_ ns: NSString, at i: Int) -> Bool {
        guard i >= 0, i < ns.length else { return false }
        guard let scalar = UnicodeScalar(ns.character(at: i)) else { return false }
        return vimWordCharacters.contains(scalar)
    }

    private static func wordMotionForwardStart(in ns: NSString, from location: Int) -> Int {
        let len = ns.length
        guard location < len else { return len }
        var i = location
        if isWordChar(ns, at: i) {
            while i < len, isWordChar(ns, at: i) { i += 1 }
        } else if ns.character(at: i) != 10, ns.character(at: i) != 13 {
            i += 1
        }
        while i < len {
            let c = ns.character(at: i)
            if c == 10 || c == 13 { i += 1; continue }
            if isWordChar(ns, at: i) { return i }
            i += 1
        }
        return len
    }

    private static func wordMotionBackwardStart(in ns: NSString, from location: Int) -> Int {
        guard location > 0 else { return 0 }

        // Mid-word → start of this word (classic `b`).
        if location < ns.length,
           isWordChar(ns, at: location),
           isWordChar(ns, at: location - 1)
        {
            var i = location
            while i > 0, isWordChar(ns, at: i - 1) { i -= 1 }
            return i
        }

        var i = location - 1
        while i > 0 {
            let c = ns.character(at: i)
            if c == 10 || c == 13 {
                i -= 1
                continue
            }
            if isWordChar(ns, at: i) {
                while i > 0, isWordChar(ns, at: i - 1) { i -= 1 }
                return i
            }
            i -= 1
        }
        return 0
    }

    private static func wordMotionForwardEnd(in ns: NSString, from location: Int) -> Int {
        let len = ns.length
        guard len > 0 else { return 0 }
        var i = location
        // If already on last char of a word, advance to next word’s end.
        if isWordChar(ns, at: i), (i + 1 >= len || !isWordChar(ns, at: i + 1)) {
            i += 1
        }
        while i < len {
            let c = ns.character(at: i)
            if c == 10 || c == 13 { i += 1; continue }
            if isWordChar(ns, at: i) {
                while i + 1 < len, isWordChar(ns, at: i + 1) { i += 1 }
                return i
            }
            i += 1
        }
        return max(0, len - 1)
    }
    /// Vim-style solid caret: cover the character under the cursor (system selection paint).
    /// Skips when a pending chord is active (underscore cursor drawn by the text view).
    func refreshBlockCaret() {
        guard vimMode == .normal else { return }
        if pendingVimKey != nil {
            let sel = textView.selectedRange()
            if sel.length != 0 {
                isUpdatingBlockCaret = true
                textView.setSelectedRange(NSRange(location: sel.location, length: 0))
                isUpdatingBlockCaret = false
            }
            textView.updateInsertionPointStateAndRestartTimer(true)
            return
        }
        isUpdatingBlockCaret = true
        defer { isUpdatingBlockCaret = false }

        var sel = textView.selectedRange()
        let ns = textView.string as NSString

        // Clamp off AppKit's trailing empty extra-line (no gutter, not editable in Normal).
        if let storage = textView.textStorage {
            let clamped = MarkdownBridge.caretLocationClampedOffTrailingEmpty(
                caretLocation: sel.location,
                in: storage
            )
            if clamped != sel.location {
                sel = NSRange(location: clamped, length: 0)
                textView.setSelectedRange(sel)
            }
        }

        let loc = sel.location
        if loc >= ns.length {
            textView.updateInsertionPointStateAndRestartTimer(true)
            return
        }

        // Newlines and the task-checkbox attachment fall back to the custom-drawn
        // caret: selection paint is the same accent as the `[!]` / `[x]` box, so a
        // one-character selection there swallows the marker.
        let ch = ns.character(at: loc)
        let isAttachment = textView.textStorage?.attribute(.attachment, at: loc, effectiveRange: nil) != nil
        if ch == 10 || ch == 13 || isAttachment {
            if sel.length != 0 {
                textView.setSelectedRange(NSRange(location: loc, length: 0))
            }
            textView.updateInsertionPointStateAndRestartTimer(true)
            return
        }

        let block = NSRange(location: loc, length: 1)
        if sel != block {
            textView.setSelectedRange(block)
        }
    }

    func collapseSelectionToCaret() {
        let sel = textView.selectedRange()
        if sel.length > 0 {
            textView.setSelectedRange(NSRange(location: sel.location, length: 0))
        }
    }

    private func moveCaretAfterCharacterIfPossible() {
        let loc = textView.selectedRange().location
        let ns = textView.string as NSString
        guard loc < ns.length else { return }
        let ch = ns.character(at: loc)
        if ch == 10 || ch == 13 { return } // stay before newline (EOL insert)
        textView.setSelectedRange(NSRange(location: loc + 1, length: 0))
    }

    private func moveCaretToParagraphEdge(end: Bool) {
        let sel = textView.selectedRange()
        let ns = textView.string as NSString
        var start = 0
        var lineEnd = 0
        var contentsEnd = 0
        ns.getParagraphStart(&start, end: &lineEnd, contentsEnd: &contentsEnd, for: sel)
        let loc = end ? contentsEnd : start
        textView.setSelectedRange(NSRange(location: loc, length: 0))
    }
}

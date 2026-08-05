import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    // MARK: - Private — Live Preview

    /// Insert Tab / Shift+Tab: nest or unnest the caret’s list/task line (2 spaces per level).
    /// Returns `true` when the line was a list item and indent changed (or outdent refused at root).
    @discardableResult
    func adjustListIndent(delta: Int) -> Bool {
        guard !isApplyingDocument, vimMode == .insert else { return false }
        restyleWorkItem?.cancel()
        hideWordCompletion()

        if let active = activeSourceLine {
            syncLineAtIndex(active)
        }

        let caret = currentMarkdownCaret()
        var lines = markdownLines
        guard caret.line >= 0, caret.line < lines.count else { return false }
        let current = lines[caret.line]
        guard MarkdownBridge.isListLine(current) else { return false }
        guard let next = MarkdownBridge.adjustListIndent(current, delta: delta) else {
            return true // list line but no-op (e.g. outdent at root)
        }
        lines[caret.line] = next
        if MarkdownBridge.taskState(in: next) != nil {
            MarkdownBridge.reconcileTaskTree(around: caret.line, in: &lines)
        }
        markdownSource = lines.joined(separator: "\n")

        let step = MarkdownBridge.listIndentStepSpaces * delta
        var column = max(0, caret.column + step)
        column = MarkdownBridge.markdownColumnAfterTaskSlugToggle(
            markdownLine: next,
            column: column,
            expanding: true
        )
        let target = MarkdownBridge.MarkdownCaret(line: caret.line, column: column)
        activeSourceLine = caret.line
        liveRestyle(to: target, animateScroll: false)
        snapTaskLineCaretIfNeeded()
        delegate?.editorDidChangeText(self)
        updateLineNumberGutter()
        return true
    }

    /// Split the active line in markdown space and continue task/list indent.
    func insertNewlineContinuingList() {
        guard !isApplyingDocument else { return }
        restyleWorkItem?.cancel()

        // Flush only a line that is already raw in the view. Do not flip `activeSourceLine`
        // before caret mapping — that breaks decorated→markdown column mapping (headings).
        if let active = activeSourceLine {
            syncLineAtIndex(active)
        }

        let caret = currentMarkdownCaret()
        let lineIdx = caret.line
        var lines = markdownLines
        while lines.count <= lineIdx {
            lines.append("")
        }

        let current = lines[lineIdx]
        let ns = current as NSString
        let splitAt = max(0, min(caret.column, ns.length))
        let continuation = MarkdownBridge.listContinuationPrefix(for: current)
        RoobytesDebugLog.event(
            "insertNewline caret=\(lineIdx):\(caret.column) split=\(splitAt) cont=\(continuation.debugDescription) lines=\(lines.count)→\(lines.count + 1)"
        )

        // Empty list/task item: Enter removes the prefix.
        if !continuation.isEmpty {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            let prefixOnly = trimmed == continuation.trimmingCharacters(in: .whitespaces)
            if prefixOnly {
                RoobytesDebugLog.event("insertNewline: empty list item → strip prefix")
                lines[lineIdx] = ""
                markdownSource = lines.joined(separator: "\n")
                activeSourceLine = lineIdx
                liveRestyle(to: MarkdownBridge.MarkdownCaret(line: lineIdx, column: 0))
                delegate?.editorDidChangeText(self)
                return
            }
        }

        // Headings: Enter at/before the title must not orphan the body as a plain line
        // above a still-rendered `### Title` (looks like a duplicated heading).
        if let markerLen = MarkdownBridge.headingMarkerLength(current), splitAt <= markerLen {
            shiftFoldsForInsert(count: 1, at: lineIdx + 1)
            lines.insert(continuation, at: lineIdx + 1)
            reconcileAfterTaskInsert(at: lineIdx + 1, in: &lines)
            markdownSource = lines.joined(separator: "\n")
            activeSourceLine = lineIdx + 1
            liveRestyle(to: MarkdownBridge.MarkdownCaret(line: lineIdx + 1, column: (continuation as NSString).length))
            delegate?.editorDidChangeText(self)
            return
        }

        let before = ns.substring(to: splitAt)
        let after = ns.substring(from: splitAt)
        lines[lineIdx] = before
        shiftFoldsForInsert(count: 1, at: lineIdx + 1)
        lines.insert(continuation + after, at: lineIdx + 1)
        reconcileAfterTaskInsert(at: lineIdx + 1, in: &lines)
        markdownSource = lines.joined(separator: "\n")

        activeSourceLine = lineIdx + 1
        let caretCol = (continuation as NSString).length
        liveRestyle(to: MarkdownBridge.MarkdownCaret(line: lineIdx + 1, column: caretCol))
        delegate?.editorDidChangeText(self)
    }

    /// When Enter / `o` creates an open task under a done parent, reopen ancestors.
    private func reconcileAfterTaskInsert(at lineIdx: Int, in lines: inout [String]) {
        guard lines.indices.contains(lineIdx),
              MarkdownBridge.taskState(in: lines[lineIdx]) != nil
        else { return }
        MarkdownBridge.reconcileTaskTree(around: lineIdx, in: &lines)
    }

    /// Drop a plain mirror line sitting immediately above the same heading body.
    private func scrubDuplicateHeadingBodies() {
        var lines = markdownLines
        var i = 0
        var changed = false
        while i < lines.count - 1 {
            if let body = MarkdownBridge.headingBody(lines[i + 1]), !body.isEmpty, body == lines[i] {
                lines.remove(at: i)
                changed = true
                continue
            }
            i += 1
        }
        if changed {
            markdownSource = lines.joined(separator: "\n")
        }
    }

    /// When the caret moves to another line, reveal that line as raw markdown.
    func updateActiveSourceLineFromSelection() {
        let lineIdx = caretLineIndex()
        guard lineIdx != activeSourceLine else { return }
        restyleWorkItem?.cancel()

        let previous = activeSourceLine
        // Previous active line is still raw in the view until we restyle — flush it.
        if let prev = previous {
            syncLineAtIndex(prev)
        }

        // Map caret from the (possibly decorated) destination line → markdown column
        // while activeSourceLine is still the previous value.
        var caretBefore = currentMarkdownCaret()
        let lines = markdownLines
        if lineIdx >= 0, lineIdx < lines.count {
            caretBefore.column = MarkdownBridge.markdownColumnAfterTaskSlugToggle(
                markdownLine: lines[lineIdx],
                column: caretBefore.column,
                expanding: true
            )
        }
        activeSourceLine = lineIdx
        let target = MarkdownBridge.MarkdownCaret(line: lineIdx, column: caretBefore.column)
        liveRestyle(to: target, replacingOnly: [previous, lineIdx].compactMap { $0 })
        snapTaskLineCaretIfNeeded()
    }

    func snapTaskLineCaretIfNeeded() {
        // Only when the active line is already raw source (slug gap between `]` and body).
        guard activeSourceLine == caretLineIndex() else { return }
        let para = currentParagraphText()
        let offset = caretOffsetInParagraph()
        guard let snapped = MarkdownBridge.snapTaskCaretOffset(in: para, offset: offset),
              snapped != offset
        else { return }

        isSnappingCaret = true
        setCaretOffsetInParagraph(snapped)
        isSnappingCaret = false
        if vimMode == .normal {
            refreshBlockCaret()
        }
    }

    func restylePreservingMarkdownCaret(delay: TimeInterval) {
        restyleWorkItem?.cancel()
        let caret = currentMarkdownCaret()
        let restoreVisual = vimMode == .visual
        let anchor = visualAnchor
        let visualEnd = visualCaret
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Format / delayed restyles: keep scroll pin subtle (no long glide).
            self.liveRestyle(to: caret, animateScroll: false)
            if restoreVisual,
               self.vimMode == .visual,
               let anchor,
               let visualEnd
            {
                self.visualAnchor = anchor
                self.visualCaret = visualEnd
                self.applyVisualSelection()
            }
        }
        restyleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func liveRestylePreservingMarkdownCaret() {
        liveRestyle(to: currentMarkdownCaret())
    }

    func currentMarkdownCaret() -> MarkdownBridge.MarkdownCaret {
        guard let storage = textView.textStorage else {
            return MarkdownBridge.MarkdownCaret(line: 0, column: 0)
        }
        return MarkdownBridge.markdownCaret(
            attributedLocation: textView.selectedRange().location,
            attributed: storage,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines
        )
    }

    func liveRestyle(
        to caret: MarkdownBridge.MarkdownCaret,
        animateScroll: Bool = false,
        replacingOnly lineIndices: [Int]? = nil
    ) {
        _ = animateScroll // scroll animations disabled for now
        guard !isApplyingDocument else { return }
        restyleWorkItem?.cancel()
        // Do NOT sync activeSourceLine from the view here — the newly activated line
        // is often still decorated (☐ / •) until we replace storage. Syncing would
        // corrupt markdownSource (e.g. overwrite `+ [ ]` with `☐…`).
        scrubDuplicateHeadingBodies()

        let mdRevision = markdownRevision
        let mdLineCount = markdownLines.count
        let hasFence = markdownSource.contains("```")
        let uniqueLines = Array(Set(lineIndices ?? [])).sorted()
        let canIncremental =
            foldedParentLines.isEmpty
            && !hasFence
            && !lastRestyleHadCodeFence
            && mdRevision == lastRestyleMarkdownRevision
            && lastRestyleMarkdownRevision >= 0
            && mdLineCount == lastRestyleMarkdownLineCount
            && !uniqueLines.isEmpty
            && uniqueLines.count <= 4

        if canIncremental, liveRestyleIncremental(lines: uniqueLines, caret: caret) {
            lastRestyleActiveLine = activeSourceLine
            lastRestyleHadCodeFence = false
            return
        }

        liveRestyleFull(to: caret)
        lastRestyleMarkdownRevision = mdRevision
        lastRestyleMarkdownLineCount = mdLineCount
        lastRestyleActiveLine = activeSourceLine
        lastRestyleHadCodeFence = hasFence
    }

    /// Replace a few view lines in place (active-line swaps). Returns false → caller full-restyles.
    @discardableResult
    private func liveRestyleIncremental(lines: [Int], caret: MarkdownBridge.MarkdownCaret) -> Bool {
        guard let storage = textView.textStorage else { return false }
        let mdLines = markdownLines
        let viewNS = textView.string as NSString
        lineIndexCache.rebuildForced(from: viewNS, revision: viewTextRevision)

        // Snapshot ranges before mutating (descending replace keeps earlier offsets valid).
        let focusLine = MarkdownBridge.focusTaskLineIndex(in: mdLines)
        var jobs: [(line: Int, range: NSRange, piece: NSAttributedString)] = []
        for lineIdx in lines {
            guard lineIdx >= 0, lineIdx < mdLines.count else { return false }
            guard lineIdx < lineIndexCache.lineCount else { return false }
            let start = lineIndexCache.characterIndex(forLine: lineIdx)
            let end: Int
            if lineIdx + 1 < lineIndexCache.lineCount {
                end = lineIndexCache.characterIndex(forLine: lineIdx + 1) - 1 // exclude \n
            } else {
                end = viewNS.length
            }
            let length = max(0, end - start)
            let range = NSRange(location: start, length: length)
            guard NSMaxRange(range) <= storage.length else { return false }
            let piece = MarkdownBridge.attributedLine(
                mdLines[lineIdx],
                lineIndex: lineIdx,
                activeSourceLine: activeSourceLine,
                focusLineIndex: focusLine
            )
            jobs.append((lineIdx, range, piece))
        }

        let clip = scrollView.contentView
        let scrollBefore = clip.bounds.origin
        let anchorDocY = lineFragmentOriginY(atCharacter: textView.selectedRange().location)

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        textView.undoManager?.disableUndoRegistration()
        isApplyingDocument = true
        storage.beginEditing()
        for job in jobs.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: job.range, with: job.piece)
        }
        storage.endEditing()
        textView.typingAttributes = MarkdownBridge.bodyAttributes(block: .paragraph)
        viewTextRevision &+= 1
        invalidateSourceLineParagraphIndex()
        refreshSourceLineParagraphIndexIfNeeded()

        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }

        let loc = MarkdownBridge.attributedLocation(
            for: caret,
            attributed: storage,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: mdLines,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        isSnappingCaret = true
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        isSnappingCaret = false
        snapTaskLineCaretIfNeeded()

        clip.scroll(to: scrollBefore)
        scrollView.reflectScrolledClipView(clip)

        var targetY = scrollBefore.y
        if let before = anchorDocY, let after = lineFragmentOriginY(atCharacter: loc) {
            targetY = scrollBefore.y + (after - before)
        }
        targetY = scrollYKeepingCharacterVisible(loc, padding: 48, proposedY: targetY)
        targetY = clampedScrollY(targetY)

        isApplyingDocument = false
        textView.undoManager?.enableUndoRegistration()
        NSAnimationContext.endGrouping()

        scrollDocument(toY: targetY, animated: false)
        if vimMode == .normal {
            refreshBlockCaret()
        }
        updateLineNumberGutter()
        updateBottomOverscrollPadding()
        refreshSpellChecking()
        return true
    }

    private func liveRestyleFull(to caret: MarkdownBridge.MarkdownCaret) {
        let clip = scrollView.contentView
        let scrollBefore = clip.bounds.origin
        let anchorDocY = lineFragmentOriginY(atCharacter: textView.selectedRange().location)

        let styled = MarkdownBridge.attributedString(
            from: markdownSource,
            activeSourceLine: activeSourceLine,
            foldedParentLines: foldedParentLines
        )

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        textView.undoManager?.disableUndoRegistration()
        isApplyingDocument = true
        textView.textStorage?.setAttributedString(styled)
        textView.typingAttributes = MarkdownBridge.bodyAttributes(block: .paragraph)
        viewTextRevision &+= 1
        invalidateSourceLineParagraphIndex()
        refreshSourceLineParagraphIndexIfNeeded()

        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }

        let loc = MarkdownBridge.attributedLocation(
            for: caret,
            attributed: styled,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        isSnappingCaret = true
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        isSnappingCaret = false
        snapTaskLineCaretIfNeeded()

        clip.scroll(to: scrollBefore)
        scrollView.reflectScrolledClipView(clip)

        var targetY = scrollBefore.y
        if let before = anchorDocY, let after = lineFragmentOriginY(atCharacter: loc) {
            targetY = scrollBefore.y + (after - before)
        }
        targetY = scrollYKeepingCharacterVisible(loc, padding: 48, proposedY: targetY)
        targetY = clampedScrollY(targetY)

        isApplyingDocument = false
        textView.undoManager?.enableUndoRegistration()
        NSAnimationContext.endGrouping()

        scrollDocument(toY: targetY, animated: false)

        if vimMode == .normal {
            refreshBlockCaret()
        }
        updateLineNumberGutter()
        updateBottomOverscrollPadding()
        refreshSpellChecking()
    }

    /// Restyles replace attributed text and wipe AppKit spelling marks.
    /// Recheck the Insert-mode raw active line; clear marks in Normal / elsewhere.
    func refreshSpellChecking() {
        guard let storage = textView.textStorage else { return }
        refreshSourceLineParagraphIndexIfNeeded()
        let full = NSRange(location: 0, length: storage.length)
        if full.length > 0 {
            textView.setSpellingState(0, range: full)
        }
        guard textView.isContinuousSpellCheckingEnabled,
              vimMode == .insert,
              let active = activeSourceLine,
              let start = MarkdownBridge.visibleParagraphStart(
                forSourceLine: active,
                in: storage,
                sourceLineParagraphIndex: sourceLineParagraphIndex
              )
        else { return }

        let text = MarkdownBridge.visibleParagraphText(
            forSourceLine: active,
            in: storage,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        ) ?? ""
        let length = (text as NSString).length
        guard length > 0 else { return }
        let range = NSRange(location: start, length: length)
        guard NSMaxRange(range) <= storage.length else { return }

        textView.checkText(
            in: range,
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: [:]
        )
    }

    private func invalidateSourceLineParagraphIndex() {
        sourceLineParagraphIndex = nil
        sourceLineParagraphIndexRevision = -1
    }

    func refreshSourceLineParagraphIndexIfNeeded() {
        guard sourceLineParagraphIndexRevision != viewTextRevision else { return }
        guard let storage = textView.textStorage else {
            sourceLineParagraphIndex = nil
            sourceLineParagraphIndexRevision = viewTextRevision
            return
        }
        sourceLineParagraphIndex = MarkdownBridge.buildSourceLineParagraphIndex(in: storage)
        sourceLineParagraphIndexRevision = viewTextRevision
    }
    func renderCurrentMode() {
        let styled = MarkdownBridge.attributedString(
            from: markdownSource,
            activeSourceLine: activeSourceLine,
            foldedParentLines: foldedParentLines
        )
        textView.isRichText = true
        textView.textStorage?.setAttributedString(styled)
        textView.typingAttributes = MarkdownBridge.bodyAttributes(block: .paragraph)
        viewTextRevision &+= 1
        invalidateSourceLineParagraphIndex()
        refreshSourceLineParagraphIndexIfNeeded()
        updateLineNumberGutter()
        updateBottomOverscrollPadding()
        refreshSpellChecking()
    }

    /// Write view line for markdown `lineIdx` into `markdownSource` only when the view shows raw source.
    /// Resolves the paragraph via `mdSourceLine` — never by view line ordinal (folds shift those).
    func syncLineAtIndex(_ lineIdx: Int) {
        guard let storage = textView.textStorage else { return }
        refreshSourceLineParagraphIndexIfNeeded()

        // Backspace at column 0 joins into the previous paragraph. The caret then sits on
        // that neighbor’s `mdSourceLine` while `activeSourceLine` is still the absorbed line.
        // Reconcile before any SKIP — otherwise Esc restyles the orphan as a “new” plain line.
        if lineIdx == activeSourceLine, lineIdx > 0 {
            let prev = lineIdx - 1
            let joinedIntoPrev: Bool = {
                if let caretSrc = mdSourceLineAtCaret(in: storage), caretSrc == prev {
                    return true
                }
                return MarkdownBridge.sourceLinesShareParagraph(
                    lineIdx,
                    prev,
                    in: storage,
                    sourceLineParagraphIndex: sourceLineParagraphIndex
                )
            }()
            if joinedIntoPrev {
                reconcileBackspaceJoin(absorbed: lineIdx, into: prev, storage: storage)
                return
            }
        }

        let viewLine: String
        if let found = MarkdownBridge.visibleParagraphText(
            forSourceLine: lineIdx,
            in: storage,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        ), !found.isEmpty {
            viewLine = found
        } else if lineIdx == activeSourceLine {
            // Caret paragraph must belong to this source line.
            if let caretSrc = mdSourceLineAtCaret(in: storage), caretSrc != lineIdx {
                RoobytesDebugLog.event("syncLine[\(lineIdx)] SKIP: caret on source line \(caretSrc)")
                return
            }
            let para = currentParagraphText()
            if para.isEmpty {
                // Emptying the last line (backspacing a fresh `+ ` at EOF) leaves a paragraph with
                // no characters, so an empty `para` is the truth here. Skipping left stale markdown
                // that the next restyle resurrected, making bottom-line edits look frozen.
                guard MarkdownBridge.caretInTrailingEmptyParagraph(
                    caretLocation: textView.selectedRange().location,
                    in: storage
                ), lineIdx == markdownLines.count - 1 else {
                    RoobytesDebugLog.event("syncLine[\(lineIdx)] SKIP: active paragraph empty")
                    return
                }
                viewLine = ""
            } else {
                viewLine = para
            }
        } else {
            RoobytesDebugLog.event("syncLine[\(lineIdx)] SKIP: paragraph not found")
            return
        }
        if MarkdownBridge.looksLikeDecoratedPreview(viewLine) {
            // Active line is always raw in the view. Decorated text here means the
            // wrong paragraph was resolved (join / stale attributes) — never write glyphs.
            RoobytesDebugLog.event("syncLine[\(lineIdx)] SKIP decorated: \(viewLine.prefix(30))")
            return
        }

        var mdLines = markdownLines
        while mdLines.count <= lineIdx {
            mdLines.append("")
        }

        if let body = MarkdownBridge.headingBody(mdLines[lineIdx]), body == viewLine {
            return
        }
        if lineIdx != activeSourceLine, isDecoratedBlockLine(lineIdx) {
            RoobytesDebugLog.event("syncLine[\(lineIdx)] SKIP decoratedBlock")
            return
        }

        let previous = mdLines[lineIdx]
        let becameDone =
            MarkdownBridge.taskState(in: previous) != .done
            && MarkdownBridge.taskState(in: viewLine) == .done

        if previous != viewLine {
            RoobytesDebugLog.event("syncLine[\(lineIdx)] \(previous.prefix(40).debugDescription) → \(viewLine.prefix(40).debugDescription)")
        }

        mdLines[lineIdx] = viewLine

        // Delete-forward across a newline joins paragraphs in the view but leaves
        // the next markdown line intact → plain duplicate on restyle (e.g. e2e…).
        if lineIdx == activeSourceLine {
            let hidden = MarkdownBridge.hiddenLineIndices(
                foldedParents: foldedParentLines,
                lines: mdLines
            )
            if let drop = MarkdownBridge.lineIndexAbsorbedAfterJoin(
                activeLine: lineIdx,
                activeViewText: viewLine,
                markdownLines: mdLines,
                attributed: storage,
                hiddenByFold: hidden
            ) {
                RoobytesDebugLog.event("syncLine[\(lineIdx)] drop absorbed neighbor \(drop)")
                mdLines.remove(at: drop)
                foldedParentLines = MarkdownBridge.foldsAfterDeleting(
                    drop..<(drop + 1),
                    from: foldedParentLines
                )
                invalidateIncrementalRestyle()
            }
        }

        markdownSource = mdLines.joined(separator: "\n")

        if becameDone {
            celebrateTaskCompleted(atLine: lineIdx)
        }
    }

    /// Active line was backspace-joined into `target` — merge markdown and move Insert there.
    private func reconcileBackspaceJoin(absorbed: Int, into target: Int, storage: NSTextStorage) {
        var mdLines = markdownLines
        guard absorbed > target,
              absorbed < mdLines.count,
              target >= 0,
              target < mdLines.count
        else { return }

        let joinedView =
            MarkdownBridge.visibleParagraphText(
                forSourceLine: target,
                in: storage,
                sourceLineParagraphIndex: sourceLineParagraphIndex
            )
            ?? currentParagraphText()
        let merged = MarkdownBridge.markdownAfterBackspaceJoin(
            targetLine: mdLines[target],
            absorbedLine: mdLines[absorbed],
            joinedViewText: joinedView.isEmpty ? nil : joinedView
        )
        RoobytesDebugLog.event(
            "syncLine[\(absorbed)] backspace-join into \(target): \(mdLines[target].prefix(30).debugDescription) + \(mdLines[absorbed].prefix(30).debugDescription) → \(merged.prefix(40).debugDescription)"
        )
        mdLines[target] = merged
        mdLines.remove(at: absorbed)
        foldedParentLines = MarkdownBridge.foldsAfterDeleting(
            absorbed..<(absorbed + 1),
            from: foldedParentLines
        )
        markdownSource = mdLines.joined(separator: "\n")
        activeSourceLine = target
        invalidateIncrementalRestyle()

        // View still has the pre-join layout / stale mdSourceLine tags. Rebuild now so
        // Esc (or the next key) does not incremental-replace the wrong ranges.
        let col = min(
            textView.selectedRange().location,
            (merged as NSString).length
        )
        // Caret UTF-16 within the merged line: prefer keeping relative offset via view.
        let caretCol: Int
        if let start = MarkdownBridge.visibleParagraphStart(
            forSourceLine: target,
            in: storage,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        ) {
            caretCol = max(0, textView.selectedRange().location - start)
        } else {
            caretCol = min(max(0, col), (merged as NSString).length)
        }
        liveRestyle(
            to: MarkdownBridge.MarkdownCaret(line: target, column: caretCol),
            animateScroll: false
        )
    }

    /// Structural markdown edits (join/split line count) must not use incremental restyle.
    private func invalidateIncrementalRestyle() {
        lastRestyleMarkdownRevision = -1
        lastRestyleMarkdownLineCount = -1
    }

    /// `mdSourceLine` for the caret paragraph, if tagged.
    private func mdSourceLineAtCaret(in storage: NSTextStorage) -> Int? {
        MarkdownBridge.sourceLine(
            atCaretLocation: textView.selectedRange().location,
            in: storage
        )
    }

    /// True when storage still has heading/task decoration (not raw `#` / `+ [ ]` source).
    private func isDecoratedBlockLine(_ lineIdx: Int) -> Bool {
        guard let storage = textView.textStorage else { return false }
        refreshSourceLineParagraphIndexIfNeeded()
        guard let loc = MarkdownBridge.visibleParagraphStart(
            forSourceLine: lineIdx,
            in: storage,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        ),
              loc < storage.length
        else { return false }
        let block = storage.attribute(.mdBlock, at: loc, effectiveRange: nil) as? String
        let plain = MarkdownBridge.visibleParagraphText(
            forSourceLine: lineIdx,
            in: storage,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        ) ?? ""
        let trimmed = plain.trimmingCharacters(in: .whitespaces)
        if let block, ["h1", "h2", "h3", "h4"].contains(block), !trimmed.hasPrefix("#") {
            return true
        }
        if block == MDBlock.task.rawValue, !trimmed.hasPrefix("+ ["), !trimmed.hasPrefix("- ["),
           !trimmed.hasPrefix("* [")
        {
            return true
        }
        return false
    }

    func syncMarkdownFromView() {
        if let active = activeSourceLine {
            syncLineAtIndex(active)
        } else if !foldedParentLines.isEmpty {
            // Folded children are absent from storage — keep `markdownSource`.
            pruneInvalidFolds()
            return
        } else if let storage = textView.textStorage {
            markdownSource = MarkdownBridge.markdown(from: storage)
        }
        pruneInvalidFolds()
    }
    func ensureBulletPrefix() {
        guard let storage = self.textView.textStorage else { return }
        let selected = self.textView.selectedRange()
        let ns = storage.string as NSString
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: selected)
        let content = ns.substring(with: NSRange(location: start, length: max(0, contentsEnd - start)))
        if !content.hasPrefix("• "), !content.hasPrefix("- "), !content.hasPrefix("* "), !content.hasPrefix("+ ") {
            storage.insert(
                NSAttributedString(string: "+ ", attributes: self.textView.typingAttributes),
                at: start
            )
            self.textView.didChangeText()
        }
    }
}

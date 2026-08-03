import AppKit

@MainActor
extension EditorViewController {
    func caretLineIndex() -> Int {
        if textView.textStorage != nil {
            return currentMarkdownCaret().line
        }
        rebuildLineIndexCache()
        let sel = textView.selectedRange()
        return lineIndexCache.lineIndex(at: sel.location)
    }

    private func caretViewLineIndex() -> Int {
        lineIndexCache.lineIndex(at: textView.selectedRange().location)
    }

    func rebuildLineIndexCache() {
        lineIndexCache.rebuildForced(from: textView.string, revision: viewTextRevision)
        lineNumberGutter.lineIndexCache = lineIndexCache
    }

    /// Sync caret line + digit width, then redraw the gutter.
    func updateLineNumberGutter() {
        let previousCurrent = lineNumberGutter.currentLine
        let previousLineCount = lineNumberGutter.lineIndexCache.lineCount
        rebuildLineIndexCache()
        let current = caretViewLineIndex()
        lineNumberGutter.currentLine = current
        let width = lineNumberGutter.preferredWidth(forLineCount: lineIndexCache.lineCount)
        let lineCountChanged = previousLineCount != lineIndexCache.lineCount
        let lineChanged = previousCurrent != current
        var widthChanged = false
        if abs((gutterWidthConstraint?.constant ?? 0) - width) > 0.5 {
            gutterWidthConstraint?.constant = width
            widthChanged = true
        }
        if lineCountChanged || lineChanged || widthChanged {
            lineNumberGutter.needsDisplay = true
        }
    }

    /// Half a viewport of blank space below the last line (scroll past the end).
    /// Uses document height (`minSize`), not `contentInsets` — insets shrink the
    /// scroller track so the knob looks “stuck” mid-window at end-of-file.
    func updateBottomOverscrollPadding() {
        let visibleH = scrollView.contentView.bounds.height
        guard visibleH > 0 else { return }

        let bottom = max(160, visibleH * 0.5)
        lastOverscrollVisibleHeight = visibleH

        // Clear any legacy inset-based overscroll.
        let zero = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        if scrollView.contentInsets.bottom > 0.5 || scrollView.contentView.contentInsets.bottom > 0.5
            || scrollView.contentInsets.top > 0.5 || scrollView.contentView.contentInsets.top > 0.5
        {
            scrollView.contentInsets = zero
            scrollView.contentView.contentInsets = zero
        }

        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let topPad = textView.textContainerOrigin.y
        let needed = ceil(max(used.maxY + topPad + bottom, visibleH))

        if abs(textView.minSize.height - needed) > 0.5 {
            textView.minSize = NSSize(width: 0, height: needed)
        }
        var frame = textView.frame
        if abs(frame.height - needed) > 0.5 {
            frame.size.height = needed
            textView.frame = frame
        }
    }
}

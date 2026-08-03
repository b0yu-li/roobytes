import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    // MARK: - Insert word completion (buffer source)

    func hideWordCompletion() {
        wordCompletion.hide()
    }

    func acceptWordCompletion() {
        guard let word = wordCompletion.selectedCandidate else {
            hideWordCompletion()
            return
        }
        let prefix = wordCompletion.prefix
        guard let suffix = BufferWordIndex.ghostSuffix(candidate: word, prefix: prefix),
              !suffix.isEmpty
        else {
            hideWordCompletion()
            return
        }
        hideWordCompletion()
        textView.insertText(suffix, replacementRange: textView.selectedRange())
    }

    func refreshWordCompletion() {
        guard RoobytesSettings.shared.wordCompletion,
              vimMode == .insert,
              vimCommandLine == nil,
              !isVimHelpVisible,
              !isTipVisible
        else {
            hideWordCompletion()
            return
        }

        // Read the prefix from the live text view (not markdownSource) so glyph
        // geometry and the token under the caret always agree.
        let caretLoc = textView.selectedRange().location
        let ns = textView.string as NSString
        guard caretLoc <= ns.length else {
            hideWordCompletion()
            return
        }
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        ns.getParagraphStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: min(caretLoc, max(0, ns.length - 1)), length: 0)
        )
        let col = caretLoc - lineStart
        let line = ns.substring(with: NSRange(location: lineStart, length: max(0, contentsEnd - lineStart)))
        guard let (prefix, _) = BufferWordIndex.prefixAtCaret(line: line, utf16Column: col)
        else {
            hideWordCompletion()
            return
        }
        let excluded = BufferWordIndex.fullWordAtCaret(line: line, utf16Column: col)
        ensureWordIndex()
        let hits = wordIndex.candidates(matchingPrefix: prefix, excluding: excluded)
        guard !hits.isEmpty,
              let anchors = wordCompletionAnchors(prefixUTF16Length: (prefix as NSString).length)
        else {
            hideWordCompletion()
            return
        }
        wordCompletion.show(
            candidates: hits,
            prefix: prefix,
            menuOriginInHost: anchors.menu,
            ghostOriginInHost: anchors.ghost,
            editorFont: textView.typingAttributes[.font] as? NSFont ?? RoobytesFont.regular(size: 13),
            hostBounds: view.bounds.size
        )
    }

    /// Menu under the typed prefix; ghost after the caret.
    /// Uses layout-manager glyph bounds in text-view space (no screen round-trip —
    /// `firstRect` + convertFromScreen was clamping the panel to the right edge).
    func wordCompletionAnchorsForCurrentPrefix() -> (menu: NSPoint, ghost: NSPoint)? {
        wordCompletionAnchors(prefixUTF16Length: (wordCompletion.prefix as NSString).length)
    }

    private func wordCompletionAnchors(prefixUTF16Length: Int) -> (menu: NSPoint, ghost: NSPoint)? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return nil }

        let caretLoc = textView.selectedRange().location
        let prefixLen = max(0, min(prefixUTF16Length, caretLoc))
        let prefixStart = caretLoc - prefixLen
        let storageLen = textView.textStorage?.length ?? textView.string.utf16.count
        guard caretLoc <= storageLen, storageLen > 0 else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let containerOrigin = textView.textContainerOrigin

        let probe = min(caretLoc, max(0, storageLen - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: probe)
        var lineRange = NSRange()
        // Full line fragment (not used-rect) so we clear task line-height boxes.
        let lineFrag = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineRange
        )
        let lineInText = lineFrag.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)

        let prefixRange = NSRange(location: prefixStart, length: prefixLen)
        let prefixGlyphs = layoutManager.glyphRange(
            forCharacterRange: prefixRange,
            actualCharacterRange: nil
        )
        var prefixInText = layoutManager.boundingRect(forGlyphRange: prefixGlyphs, in: textContainer)
        prefixInText = prefixInText.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
        if prefixLen == 0 {
            prefixInText = NSRect(x: lineInText.minX, y: lineInText.minY, width: 0, height: lineInText.height)
        }

        // Insertion point = right edge of the glyph before the caret.
        let caretXInText: CGFloat
        if prefixLen > 0 {
            caretXInText = prefixInText.maxX
        } else if caretLoc > 0 {
            let prevGlyphs = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: caretLoc - 1, length: 1),
                actualCharacterRange: nil
            )
            let prev = layoutManager.boundingRect(forGlyphRange: prevGlyphs, in: textContainer)
                .offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
            caretXInText = prev.maxX
        } else {
            caretXInText = lineInText.minX
        }

        let prefixInHost = view.convert(prefixInText, from: textView)
        let lineInHost = view.convert(lineInText, from: textView)
        let caretInHost = view.convert(
            NSPoint(x: caretXInText, y: lineInText.midY),
            from: textView
        )

        let hostH = view.bounds.height
        let font = textView.typingAttributes[.font] as? NSFont ?? RoobytesFont.regular(size: 13)
        // topAnchor constants are distances from the top edge.
        let lineTopFromTop = hostH - lineInHost.maxY
        let lineBottomFromTop = hostH - lineInHost.minY

        let menu = NSPoint(
            x: prefixInHost.minX,
            y: lineBottomFromTop + 6
        )
        let ghost = NSPoint(
            x: caretInHost.x,
            y: lineTopFromTop + max(0, (lineInHost.height - font.boundingRectForFont.height) * 0.5)
        )
        return (menu, ghost)
    }

    func refreshWordCompletionAccent() {
        wordCompletion.refreshAccent()
    }
}

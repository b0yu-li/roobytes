import AppKit

@MainActor
extension EditorViewController {
    func celebrateTaskCompleted(atLine lineIdx: Int) {
        TypewriterSound.shared.playTaskDone()
        guard let point = celebrationPoint(forLine: lineIdx) else { return }
        // Burst in the text view (flipped) at document coords — avoids a bad
        // convert+Y-flip that landed confetti below the task.
        ConfettiCelebration.burst(in: textView, at: point)
    }

    /// Midpoint of the checkbox / marker on the line (text-view coordinates).
    private func celebrationPoint(forLine lineIdx: Int) -> NSPoint? {
        guard let layout = textView.layoutManager,
              let storage = textView.textStorage,
              textView.textContainer != nil
        else { return nil }
        refreshSourceLineParagraphIndexIfNeeded()
        let ns = storage.string as NSString
        guard ns.length > 0 else {
            return NSPoint(x: textView.bounds.midX, y: textView.textContainerOrigin.y + 12)
        }
        let loc = MarkdownBridge.attributedLocation(
            for: MarkdownBridge.MarkdownCaret(line: lineIdx, column: 0),
            attributed: storage,
            markdown: markdownSource,
            activeSourceLine: activeSourceLine,
            markdownLines: markdownLines,
            sourceLineParagraphIndex: sourceLineParagraphIndex
        )
        let idx = max(0, min(loc, ns.length - 1))
        let glyph = layout.glyphIndexForCharacter(at: idx)
        var effective = NSRange()
        let frag = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
        let used = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let inset = textView.textContainerOrigin
        // Checkbox sits at the start of the used rect; center vertically on the glyph box.
        let x = inset.x + used.minX + 10
        let y = inset.y + used.midY
        // used can be empty on blank lines — fall back to fragment mid.
        if used.height < 1 {
            return NSPoint(x: inset.x + 24, y: inset.y + frag.midY)
        }
        return NSPoint(x: x, y: y)
    }
}

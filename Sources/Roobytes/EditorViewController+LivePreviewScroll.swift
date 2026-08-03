import AppKit

@MainActor
extension EditorViewController {
    func clampedScrollY(_ y: CGFloat) -> CGFloat {
        let clip = scrollView.contentView
        let maxY = max(0, textView.bounds.height - clip.bounds.height)
        return min(max(0, y), maxY)
    }

    func scrollDocument(toY y: CGFloat, animated: Bool, duration: TimeInterval = 0.2) {
        // Animations disabled for now (except confetti). Always snap.
        _ = animated
        _ = duration
        let clip = scrollView.contentView
        let target = NSPoint(x: clip.bounds.origin.x, y: clampedScrollY(y))
        let from = clip.bounds.origin
        guard abs(target.y - from.y) > 0.5 || abs(target.x - from.x) > 0.5 else { return }

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        clip.animator().setBoundsOrigin(target)
        NSAnimationContext.endGrouping()
        clip.scroll(to: target)
        scrollView.reflectScrolledClipView(clip)
    }

    func isCharacterVisible(_ characterIndex: Int, padding: CGFloat) -> Bool {
        guard let layout = textView.layoutManager,
              textView.textContainer != nil
        else { return true }
        let nsLen = (textView.string as NSString).length
        guard nsLen > 0 else { return true }
        let idx = max(0, min(characterIndex, nsLen - 1))
        let glyph = layout.glyphIndexForCharacter(at: idx)
        var effective = NSRange()
        let frag = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
        let origin = textView.textContainerOrigin
        let lineMinY = origin.y + frag.minY
        let lineMaxY = origin.y + frag.maxY
        let visible = scrollView.contentView.bounds
        return lineMinY >= visible.minY + padding && lineMaxY <= visible.maxY - padding
    }

    func scrollCharacterIntoViewInstant(_ characterIndex: Int, padding: CGFloat) {
        let targetY = scrollYKeepingCharacterVisible(
            characterIndex,
            padding: padding,
            proposedY: scrollView.contentView.bounds.origin.y
        )
        scrollDocument(toY: targetY, animated: false)
    }

    /// Adjust `proposedY` so `characterIndex` stays inside the viewport with `padding`.
    func scrollYKeepingCharacterVisible(
        _ characterIndex: Int,
        padding: CGFloat,
        proposedY: CGFloat
    ) -> CGFloat {
        guard let layout = textView.layoutManager,
              textView.textContainer != nil
        else { return proposedY }
        let nsLen = (textView.string as NSString).length
        guard nsLen > 0 else { return proposedY }
        let idx = max(0, min(characterIndex, nsLen - 1))
        let glyph = layout.glyphIndexForCharacter(at: idx)
        var effective = NSRange()
        let frag = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
        let origin = textView.textContainerOrigin
        let lineMinY = origin.y + frag.minY
        let lineMaxY = origin.y + frag.maxY
        let height = scrollView.contentView.bounds.height
        var targetY = proposedY
        if lineMinY < targetY + padding {
            targetY = lineMinY - padding
        } else if lineMaxY > targetY + height - padding {
            targetY = lineMaxY + padding - height
        }
        return clampedScrollY(targetY)
    }

    /// Document Y of the line fragment containing `characterIndex` (for scroll pinning).
    func lineFragmentOriginY(atCharacter characterIndex: Int) -> CGFloat? {
        guard let layout = textView.layoutManager,
              textView.textContainer != nil
        else { return nil }
        let nsLen = (textView.string as NSString).length
        guard nsLen > 0 else { return 0 }
        let idx = max(0, min(characterIndex, nsLen - 1))
        let glyph = layout.glyphIndexForCharacter(at: idx)
        var effective = NSRange()
        let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
        return rect.origin.y
    }
}

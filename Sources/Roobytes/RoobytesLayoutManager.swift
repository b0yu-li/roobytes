import AppKit
import RoobytesObjC

/// Draws rounded, opaque chips behind `` `inline code` `` runs (mdInline == "code").
final class RoobytesLayoutManager: NSLayoutManager {
    private struct ChipCacheKey: Equatable {
        var length: Int
        var width: CGFloat
    }

    /// Chip rects in text-container coordinates (origin applied at draw time).
    private var cachedChips: [CGRect] = []
    private var chipCacheKey = ChipCacheKey(length: -1, width: -1)
    private var isDrawingBackground = false

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Nested draw can happen if glyph remapping triggers layout.
        guard !isDrawingBackground else { return }
        guard let textStorage else { return }

        let storageLength = textStorage.length
        let glyphCount = numberOfGlyphs
        guard storageLength > 0, glyphCount > 0 else { return }
        guard glyphsToShow.location < glyphCount else { return }

        let truncatedEnd = min(NSMaxRange(glyphsToShow), glyphCount)
        let truncated = NSRange(
            location: glyphsToShow.location,
            length: truncatedEnd - glyphsToShow.location
        )
        guard truncated.length > 0 else { return }

        // Glyph counts can lag behind Live Preview `setAttributedString` /
        // incremental replace. AppKit then asks to draw a glyph range whose
        // character mapping extends past `textStorage.length`, and
        // `ensureAttributesAreFixedInRange:` raises NSRangeException →
        // `NSApplication _crashOnException:` (see DiagnosticReports).
        var usedGlyphs = NSRange()
        let charRange = characterRange(forGlyphRange: truncated, actualGlyphRange: &usedGlyphs)
        guard charRange.location != NSNotFound, charRange.location < storageLength else { return }
        let safeChars = NSRange(
            location: charRange.location,
            length: min(charRange.length, storageLength - charRange.location)
        )
        guard safeChars.length > 0 else { return }

        isDrawingBackground = true
        defer { isDrawingBackground = false }

        let safeGlyphs = glyphRange(forCharacterRange: safeChars, actualCharacterRange: nil)
        guard safeGlyphs.length > 0, NSMaxRange(safeGlyphs) <= numberOfGlyphs else { return }

        // Last-resort: never let a residual AppKit range exception kill the app mid-draw.
        if let exception = RoobytesCatchException({
            super.drawBackground(forGlyphRange: safeGlyphs, at: origin)
        }) {
            RoobytesDebugLog.event(
                "drawBackground skipped \(exception.name.rawValue): \(exception.reason ?? "")"
            )
            return
        }
        drawInlineCodeChips(forGlyphRange: safeGlyphs, at: origin)
    }

    override func processEditing(
        for textStorage: NSTextStorage,
        edited editMask: NSTextStorageEditActions,
        range newCharRange: NSRange,
        changeInLength delta: Int,
        invalidatedRange invalidatedCharRange: NSRange
    ) {
        // Attribute-only edits don't move glyphs — keep chip rects.
        if editMask.contains(.editedCharacters) {
            invalidateChipCache()
        }
        super.processEditing(
            for: textStorage,
            edited: editMask,
            range: newCharRange,
            changeInLength: delta,
            invalidatedRange: invalidatedCharRange
        )
    }

    override func textContainerChangedGeometry(_ container: NSTextContainer) {
        invalidateChipCache()
        super.textContainerChangedGeometry(container)
    }

    private func invalidateChipCache() {
        cachedChips = []
        chipCacheKey = ChipCacheKey(length: -1, width: -1)
    }

    private func rebuildChipCacheIfNeeded() {
        guard let textStorage,
              let textContainer = textContainers.first
        else { return }

        let key = ChipCacheKey(
            length: textStorage.length,
            width: textContainer.containerSize.width
        )
        if key == chipCacheKey { return }
        chipCacheKey = key
        cachedChips = []
        guard textStorage.length > 0 else { return }

        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.mdInline, in: full, options: []) { value, range, _ in
            guard (value as? String) == "code", range.length > 0 else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            self.enumerateLineFragments(forGlyphRange: glyphRange) { fragRect, _, _, lineGlyphRange, _ in
                let slice = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard slice.length > 0 else { return }

                var rect = self.boundingRect(forGlyphRange: slice, in: textContainer)
                rect = rect.insetBy(dx: -2, dy: -0.5)
                rect.size.height = max(rect.height, 13)
                rect = rect.intersection(fragRect)
                guard rect.width > 1, rect.height > 1 else { return }
                self.cachedChips.append(rect)
            }
        }
    }

    private func drawInlineCodeChips(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textContainer = textContainers.first else { return }
        rebuildChipCacheIfNeeded()
        guard !cachedChips.isEmpty else { return }

        // Visible band in container coordinates.
        var visible = boundingRect(forGlyphRange: glyphsToShow, in: textContainer)
        visible = visible.insetBy(dx: -8, dy: -8)

        for var rect in cachedChips {
            guard rect.intersects(visible) else { continue }
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            let radius = min(3.5, rect.height * 0.28)
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            RoobytesAccent.codeBackground.setFill()
            path.fill()
        }
    }
}

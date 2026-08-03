import AppKit

/// Left gutter: vim hybrid line numbers (absolute on caret line, relative elsewhere).
/// Relative counts below the caret (`j`) use accent; above (`k`) use a cool steel-blue.
final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?

    /// Shared line-start table (rebuilt by the editor after text changes).
    var lineIndexCache = LineIndexCache()

    /// 0-based caret line in the text view string.
    var currentLine: Int = 0 {
        didSet {
            if oldValue != currentLine {
                needsDisplay = true
            }
        }
    }

    private static let numberSize: CGFloat = 11
    private static let horizontalPadding: CGFloat = 4
    private static let trailingGap: CGFloat = 4

    private var lastDrawnScrollY: CGFloat = .nan
    private var lastDrawnGlyphRange = NSRange(location: 0, length: 0)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Width for `digits` of the largest absolute line number (min 2).
    func preferredWidth(forLineCount lineCount: Int) -> CGFloat {
        let digits = max(2, String(max(1, lineCount)).count)
        let font = RoobytesFont.regular(size: Self.numberSize)
        let digitW = ("0" as NSString).size(withAttributes: [.font: font]).width
        return ceil(digitW * CGFloat(digits)) + Self.horizontalPadding + Self.trailingGap
    }

    /// Ask for a redraw only when the visible band meaningfully moved.
    func setNeedsDisplayForScrollIfNeeded() {
        guard let scrollView, let textView, let layout = textView.layoutManager,
              let container = textView.textContainer
        else {
            needsDisplay = true
            return
        }
        let scrollY = scrollView.contentView.bounds.origin.y
        var containerRect = textView.visibleRect
        containerRect.origin.x -= textView.textContainerOrigin.x
        containerRect.origin.y -= textView.textContainerOrigin.y
        let glyphRange = layout.glyphRange(forBoundingRect: containerRect, in: container)

        if abs(scrollY - lastDrawnScrollY) < 0.75,
           NSEqualRanges(glyphRange, lastDrawnGlyphRange)
        {
            return
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            drawGutter(dirtyRect)
        }
    }

    private func drawGutter(_ dirtyRect: NSRect) {
        RoobytesTheme.editorBackground.setFill()
        bounds.fill()

        guard let textView,
              let scrollView,
              let layout = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        let font = RoobytesFont.regular(size: Self.numberSize)
        let currentColor = RoobytesTheme.gutterCurrentLine
        let downColor = RoobytesTheme.gutterJumpDown // `j`
        let upColor = RoobytesTheme.gutterJumpUp // `k`
        let ns = textView.string as NSString

        let visible = textView.visibleRect
        var containerRect = visible
        containerRect.origin.x -= textView.textContainerOrigin.x
        containerRect.origin.y -= textView.textContainerOrigin.y
        containerRect = containerRect.insetBy(dx: 0, dy: -48)

        let glyphRange = layout.glyphRange(forBoundingRect: containerRect, in: container)
        lastDrawnScrollY = scrollView.contentView.bounds.origin.y
        lastDrawnGlyphRange = glyphRange

        if ns.length == 0 {
            let y = textView.textContainerOrigin.y
                - scrollView.contentView.bounds.origin.y
                + 8
            drawLabel("1", atY: y, font: font, color: currentColor)
            return
        }

        guard glyphRange.length > 0 else {
            drawLabel("1", atY: textView.textContainerOrigin.y + 8, font: font, color: currentColor)
            return
        }

        let origin = textView.textContainerOrigin
        let scrollY = scrollView.contentView.bounds.origin.y
        let rightEdge = bounds.maxX - Self.trailingGap
        let cache = lineIndexCache
        let caretLine = currentLine

        layout.enumerateLineFragments(forGlyphRange: glyphRange) { fragRect, _, _, fragGlyphs, _ in
            guard fragGlyphs.length > 0 else { return }
            let charIdx = layout.characterIndexForGlyph(at: fragGlyphs.location)
            if charIdx > 0, ns.character(at: charIdx - 1) != 10 {
                return
            }

            let line = cache.lineIndex(at: charIdx)
            let isCurrent = line == caretLine
            let value = isCurrent ? line + 1 : abs(line - caretLine)
            let color: NSColor
            if isCurrent {
                color = currentColor
            } else if line > caretLine {
                color = downColor // `j` / below
            } else {
                color = upColor // `k` / above
            }
            let midY = origin.y + fragRect.midY - scrollY
            self.drawLabel(String(value), atY: midY, font: font, color: color, rightEdge: rightEdge)
        }
    }

    private func drawLabel(
        _ text: String,
        atY midY: CGFloat,
        font: NSFont,
        color: NSColor,
        rightEdge: CGFloat? = nil
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let edge = rightEdge ?? (bounds.maxX - Self.trailingGap)
        let x = edge - size.width
        let y = midY - size.height / 2
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}

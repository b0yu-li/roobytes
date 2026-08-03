import AppKit

enum VimEditorMode: Equatable {
    case insert
    case normal
    /// Characterwise visual — real AppKit selection for ⌘B / ⌘I; motions extend it.
    case visual

    var toolTip: String {
        switch self {
        case .insert:
            return "Insert · Esc → Normal · Tab completes words"
        case .normal:
            return "Normal · v select · r · za fold · mf/'f focus · ]t/[t task · ^d/^u page · :w/:daily/:e!/:q/:pin/:h · 5j · dd · yy · gg/G"
        case .visual:
            return "Visual · motions extend selection · ⌘B/⌘I format · Esc → Normal"
        }
    }
}

/// Geometry for the caret ring around a task-checkbox attachment.
public enum TaskCheckboxCaret {
    /// Square a checkbox attachment paints, in view coordinates.
    ///
    /// Two traps: TextKit reports an attachment glyph's location as the **bottom**
    /// of `attachment.bounds` (it has already folded in `bounds.origin.y`), so the
    /// usual baseline math lands the rect a descender too low; and the cell is
    /// wider than the square because it carries the trailing gap.
    public static func squareRect(
        fragmentOrigin: CGPoint,
        glyphLocation: CGPoint,
        attachmentBounds: CGRect,
        containerOrigin: CGPoint
    ) -> CGRect {
        let side = attachmentBounds.height
        return CGRect(
            x: fragmentOrigin.x + glyphLocation.x + containerOrigin.x,
            y: fragmentOrigin.y + glyphLocation.y - side + containerOrigin.y,
            width: side,
            height: side
        )
    }
}

/// Characterwise Visual selection math (inclusive endpoints, like vim `v`).
public enum VimVisual {
    /// Inclusive range covering both `anchor` and `caret` (UTF-16 indices).
    public static func selectionRange(anchor: Int, caret: Int, documentLength: Int) -> NSRange {
        guard documentLength > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let a = max(0, min(anchor, documentLength - 1))
        let c = max(0, min(caret, documentLength))
        if c >= documentLength {
            let lo = min(a, documentLength)
            return NSRange(location: lo, length: documentLength - lo)
        }
        let lo = min(a, c)
        let hi = max(a, c)
        return NSRange(location: lo, length: hi - lo + 1)
    }
}

/// Text view that routes keys through simple vim Normal / Insert handling.
@MainActor
final class RoobytesEditorTextView: NSTextView {
    weak var vimHost: EditorViewController?
    private var blockCaretDirtyRect: NSRect = .zero

    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = RoobytesLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        ))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    override func keyDown(with event: NSEvent) {
        if vimHost?.handleVimKeyDown(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if vimHost?.vimMode == .normal || vimHost?.vimMode == .visual {
            return
        }
        let typed: String
        if let s = insertString as? String {
            typed = s
        } else if let attr = insertString as? NSAttributedString {
            typed = attr.string
        } else {
            return
        }
        // Never insert Escape / bare control chars from misrouted input sources.
        if typed == "\u{1b}" || typed == "\u{3}" {
            return
        }
        // A bare newline via insertText (^J, ^M, IME edge cases) must go through
        // the proper newline handler — not raw insertion — so list continuation,
        // markdown sync, and caret mapping all work.
        if typed == "\n" || typed == "\r" || typed == "\r\n" {
            TypewriterSound.shared.playInsert("\n")
            vimHost?.insertNewlineContinuingList()
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
        TypewriterSound.shared.playInsert(typed)
        if typed == "=" {
            vimHost?.tryAutoEvaluateSumAfterEquals()
        } else if typed == "(" {
            vimHost?.tryAutoEvaluateTimeRangeDuration()
        }
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(cancelOperation(_:)) {
            _ = vimHost?.handleVimEscape()
            return
        }
        if vimHost?.vimMode == .normal || vimHost?.vimMode == .visual {
            // Allow caret motion / scrolling; block edits that mutate text.
            let allowed: Set<String> = [
                "moveLeft:", "moveRight:", "moveUp:", "moveDown:",
                "moveLeftAndModifySelection:", "moveRightAndModifySelection:",
                "moveUpAndModifySelection:", "moveDownAndModifySelection:",
                "moveToBeginningOfLine:", "moveToEndOfLine:",
                "moveToBeginningOfParagraph:", "moveToEndOfParagraph:",
                "moveToBeginningOfDocument:", "moveToEndOfDocument:",
                "moveToLeftEndOfLine:", "moveToRightEndOfLine:",
                "moveWordLeft:", "moveWordRight:",
                "moveWordLeftAndModifySelection:", "moveWordRightAndModifySelection:",
                "pageUp:", "pageDown:", "scrollPageUp:", "scrollPageDown:",
                "scrollLineUp:", "scrollLineDown:",
                "moveToBeginningOfLineAndModifySelection:",
                "moveToEndOfLineAndModifySelection:",
            ]
            if allowed.contains(NSStringFromSelector(selector)) {
                super.doCommand(by: selector)
            }
            return
        }
        let deleting =
            selector == #selector(deleteBackward(_:))
            || selector == #selector(deleteForward(_:))
            || selector == #selector(deleteWordBackward(_:))
            || selector == #selector(deleteWordForward(_:))
            || selector == #selector(deleteToBeginningOfLine(_:))
            || selector == #selector(deleteToEndOfLine(_:))
        super.doCommand(by: selector)
        if deleting {
            TypewriterSound.shared.playDelete()
        }
    }

    /// Only Insert blinks. Over a character the Normal caret is a one-character
    /// selection highlight, which AppKit never blinks — so the EOL / blank-line
    /// block and the pending-chord underscore must stay steady to match.
    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        guard vimHost?.vimMode == .insert else {
            super.updateInsertionPointStateAndRestartTimer(false)
            return
        }
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
    }

    /// Solid block caret (Normal) or underscore caret (pending chord like `r`).
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard vimHost?.vimMode == .normal else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }

        // `shouldDrawInsertionPoint` keeps the caret painted between blink ticks
        // while focused, and still lets an unfocused view erase it.
        let on = flag || shouldDrawInsertionPoint
        let pending = vimHost?.pendingVimKey != nil

        if pending {
            let uRect = underscoreCaretRect(fallback: rect)
            blockCaretDirtyRect = uRect
            if on {
                RoobytesAccent.caret.setFill()
                uRect.fill()
            } else {
                setNeedsDisplay(uRect)
            }
            return
        }

        guard selectedRange().length == 0 else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }

        if let square = checkboxSquareRect(at: selectedRange().location) {
            let ring = square.insetBy(dx: -1, dy: -1)
            blockCaretDirtyRect = ring.insetBy(dx: -2, dy: -2)
            if on {
                let path = NSBezierPath(roundedRect: ring, xRadius: 4.5, yRadius: 4.5)
                path.lineWidth = 1.5
                RoobytesAccent.caret.setStroke()
                path.stroke()
            } else {
                setNeedsDisplay(blockCaretDirtyRect)
            }
            return
        }

        let block = blockCaretRect(fallback: rect)
        blockCaretDirtyRect = block
        if on {
            RoobytesAccent.caret.setFill()
            block.fill()
        } else {
            setNeedsDisplay(block)
        }
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var dirty = rect
        if vimHost?.vimMode == .normal {
            dirty = dirty.union(blockCaretDirtyRect)
            if selectedRange().length == 0 {
                dirty = dirty.union(blockCaretRect(fallback: rect))
            }
        }
        super.setNeedsDisplay(dirty, avoidAdditionalLayout: flag)
    }

    private func checkboxSquareRect(at location: Int) -> NSRect? {
        guard let layoutManager,
              let storage = textStorage,
              location >= 0,
              location < storage.length,
              let attachment = storage.attribute(.attachment, at: location, effectiveRange: nil)
              as? NSTextAttachment,
              attachment.bounds.height > 0
        else { return nil }

        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)

        return TaskCheckboxCaret.squareRect(
            fragmentOrigin: fragment.origin,
            glyphLocation: layoutManager.location(forGlyphAt: glyph),
            attachmentBounds: attachment.bounds,
            containerOrigin: textContainerOrigin
        )
    }

    private func blockCaretRect(fallback rect: NSRect) -> NSRect {
        var block = rect
        let loc = selectedRange().location
        if let square = checkboxSquareRect(at: loc) {
            return square
        }
        let ns = string as NSString

        if loc < ns.length,
           let layoutManager,
           let textContainer
        {
            let ch = ns.character(at: loc)
            if ch != 10, ch != 13 {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: loc, length: 1),
                    actualCharacterRange: nil
                )
                let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let origin = textContainerOrigin
                return NSRect(
                    x: glyphBounds.origin.x + origin.x,
                    y: glyphBounds.origin.y + origin.y,
                    width: max(glyphBounds.width, 4),
                    height: max(glyphBounds.height, rect.height)
                )
            }
        }

        // EOL / EOF — approximate one em of the typing font.
        let font = typingAttributes[.font] as? NSFont ?? RoobytesFont.regular(size: 13)
        let em = ("M" as NSString).size(withAttributes: [.font: font]).width
        block.size.width = max(em, 6)
        return block
    }

    private func underscoreCaretRect(fallback rect: NSRect) -> NSRect {
        let full = blockCaretRect(fallback: rect)
        let height: CGFloat = 2.5
        return NSRect(
            x: full.origin.x,
            y: full.maxY - height,
            width: full.width,
            height: height
        )
    }
}

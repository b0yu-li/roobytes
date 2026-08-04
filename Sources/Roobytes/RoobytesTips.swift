import AppKit
import Foundation

/// Short Roobytes tips — random pick for `:tips` / startup.
public enum RoobytesTips {
    public struct Tip: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var body: String
    }

    public static let all: [Tip] = [
        Tip(
            id: "word-complete",
            title: "Word completion",
            body: "In Insert, type 2+ letters — menu + ghost from this note. Tab/Enter accept. Toggle with :complete / :cmp or Settings."
        ),
        Tip(
            id: "esc-normal",
            title: "Normal mode",
            body: "Press Esc for Normal (Live Preview). Type i / a / I / A to Insert."
        ),
        Tip(
            id: "visual-select",
            title: "Visual select",
            body: "In Normal, press v then move (h/j/k/l, w/b/e) to select. y yanks, d or x cuts; p / P put. ⌘B / ⌘I format; Esc returns to Normal."
        ),
        Tip(
            id: "cmd-palette",
            title: "Command palette",
            body: "In Normal mode, press : then Tab to complete — try :w, :h, :daily, :folddone, :pin."
        ),
        Tip(
            id: "daily-note",
            title: "Daily note",
            body: ":daily (or :today) opens diaries/YYYY-MM-DD.md. Requires vault-root daily-notes-temp.md (and an open vault)."
        ),
        Tip(
            id: "chord-hints",
            title: "Chord hints",
            body: "After g, r, z, or m, a bottom-right hint lists the next keys (context-aware)."
        ),
        Tip(
            id: "gx",
            title: "Open links",
            body: "Put the caret on a URL and press gx (Firefox) or gX (Private)."
        ),
        Tip(
            id: "lookup-k",
            title: "Look Up",
            body: "In Normal mode, press K on a word for the system Dictionary / Look Up popover (same idea as vim keyword lookup)."
        ),
        Tip(
            id: "spell-z-equals",
            title: "Spell fix",
            body: "In Normal mode, z= replaces the word under the caret with the first macOS spelling suggestion."
        ),
        Tip(
            id: "tasks-md",
            title: "Tasks",
            body: "md marks done · mD marks open · mf toggles focus [!] · 'f jumps to focus · ]t / [t hops undone tasks."
        ),
        Tip(
            id: "folds",
            title: "Nested folds",
            body: "On a parent list item, za toggles fold · zc closes · zo opens. :folddone / :fd collapses every done [x] nest."
        ),
        Tip(
            id: "goto-file",
            title: "Go to file",
            body: "⌘P jumps vault notes by frecency — type to fuzzy-filter, Enter to open."
        ),
        Tip(
            id: "half-page",
            title: "Half-page scroll",
            body: "⌃d / ⌃u scroll half a page without moving the caret (counts work: 2⌃d)."
        ),
        Tip(
            id: "help-q",
            title: "Help & tips",
            body: ":h opens the vim reference — ⌃e/⌃y line scroll, ⌃d/⌃u half-page · :tips shows another tip · Esc or q dismisses either."
        ),
        Tip(
            id: "sound",
            title: "Sound effects",
            body: "Settings → Sound enables soft clicks for typing, motions, :w, and task-done."
        ),
        Tip(
            id: "relative-gutter",
            title: "Relative numbers",
            body: "The gutter shows absolute on the caret line; below uses accent (j), above steel-blue (k)."
        ),
        Tip(
            id: "wrapped-rows",
            title: "Wrapped lines",
            body: "Bare j / k step one wrapped row, so long paragraphs are walkable. With a count (5j) they move real lines, matching the gutter — gj / gk force rows."
        ),
        Tip(
            id: "undo",
            title: "Undo",
            body: "In Normal mode, u undoes — 3u undoes three times."
        ),
    ]

    /// Pick a random tip, preferring one different from `avoiding` id when possible.
    public static func random(avoiding previousID: String? = nil) -> Tip {
        guard all.count > 1, let previousID, !previousID.isEmpty else {
            return all.randomElement() ?? all[0]
        }
        let pool = all.filter { $0.id != previousID }
        return (pool.randomElement() ?? all.randomElement()) ?? all[0]
    }

    @MainActor
    public static func attributedText(for tip: Tip) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titlePara = NSMutableParagraphStyle()
        titlePara.paragraphSpacing = 4

        result.append(NSAttributedString(
            string: "Tip\n",
            attributes: [
                .font: RoobytesFont.regular(size: 11),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 0.8,
                .paragraphStyle: titlePara,
            ]
        ))
        result.append(NSAttributedString(
            string: tip.title + "\n",
            attributes: [
                .font: RoobytesFont.regular(size: 15),
                .foregroundColor: RoobytesAccent.bright,
                .paragraphStyle: titlePara,
            ]
        ))
        result.append(NSAttributedString(
            string: tip.body + "\n\n",
            attributes: [
                .font: RoobytesFont.regular(size: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        result.append(NSAttributedString(
            string: ":tips again  ·  Esc / q to close",
            attributes: [
                .font: RoobytesFont.regular(size: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        return result
    }
}

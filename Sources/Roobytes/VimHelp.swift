import AppKit
import Foundation

/// Human-readable Roobytes vim reference (`:h` / `:help`).
public enum VimHelp {
    public struct Row: Equatable, Sendable {
        public var keys: String
        public var blurb: String
    }

    public struct Section: Equatable, Sendable {
        public var title: String
        public var rows: [Row]
    }

    public static let title = "Roobytes vim"
    public static let subtitle = "Esc or q to close · ⌃e/⌃y line · ⌃d/⌃u page"

    public static let sections: [Section] = [
        Section(title: "Modes", rows: [
            Row(keys: "Esc", blurb: "Normal (Live Preview)"),
            Row(keys: "i a I A", blurb: "Insert · before / after / line start / end"),
            Row(keys: "o O", blurb: "Open line below / above → Insert"),
            Row(keys: "v", blurb: "Visual · select with motions · ⌘B / ⌘I format"),
            Row(keys: "Tab", blurb: "Insert: accept word completion (buffer)"),
            Row(keys: "g r z m [ ] …", blurb: "Pending chords show a context hint"),
        ]),
        Section(title: "Motion", rows: [
            Row(keys: "h j k l", blurb: "Left / down / up / right (j/k walk wrapped rows)"),
            Row(keys: "gj gk", blurb: "Down / up one wrapped row"),
            Row(keys: "0 $", blurb: "Line start / end"),
            Row(keys: "w b e", blurb: "Word forward / back / end"),
            Row(keys: "gg G", blurb: "Top / bottom"),
            Row(keys: "1–9…", blurb: "Count prefix (5j is 5 real lines, 3dd, 2⌃d)"),
        ]),
        Section(title: "Scroll", rows: [
            Row(keys: "⌃e ⌃y", blurb: "Line down / up (caret stays)"),
            Row(keys: "⌃d ⌃u", blurb: "Half-page down / up"),
            Row(keys: "zz", blurb: "Center cursor line"),
        ]),
        Section(title: "Edit", rows: [
            Row(keys: "r{char}", blurb: "Replace under caret (3rX)"),
            Row(keys: "dd", blurb: "Delete line (3dd)"),
            Row(keys: "yy", blurb: "Yank line content (strip tag / markers)"),
            Row(keys: "p P", blurb: "Put after / before"),
            Row(keys: "u", blurb: "Undo (3u)"),
            Row(keys: "K", blurb: "Look Up word under caret (Dictionary)"),
            Row(keys: "z=", blurb: "Auto-fix spelling under caret (first guess)"),
        ]),
        Section(title: "Tasks", rows: [
            Row(keys: "md", blurb: "Mark done [x]"),
            Row(keys: "mD", blurb: "Mark open [ ]"),
            Row(keys: "mf", blurb: "Toggle [!] focus"),
            Row(keys: "'f", blurb: "Jump to focus"),
            Row(keys: "]t [t", blurb: "Next / previous undone task"),
            Row(keys: "⌘↩", blurb: "Cycle [ ] / [!] → [x] → [~]"),
        ]),
        Section(title: "Folds", rows: [
            Row(keys: "za zc zo", blurb: "Toggle / close / open nested lists"),
            Row(keys: ":folddone", blurb: "Fold all done [x] parents (:fd)"),
        ]),
        Section(title: "Links", rows: [
            Row(keys: "gx gX", blurb: "Open URL · Firefox / Private"),
        ]),
        Section(title: "Ex", rows: [
            Row(keys: ":w", blurb: "Write / save"),
            Row(keys: ":e!", blurb: "Discard edits"),
            Row(keys: ":q", blurb: "Quit window"),
            Row(keys: ":pin", blurb: "Float on top"),
            Row(keys: ":daily", blurb: "Open / create today’s note (:today)"),
            Row(keys: ":folddone", blurb: "Fold all done task nests"),
            Row(keys: ":complete", blurb: "Toggle Insert word complete"),
            Row(keys: ":h", blurb: "This reference"),
            Row(keys: ":tips", blurb: "Random tip"),
        ]),
    ]

    /// Plain-text body (tests / fallback).
    public static var text: String {
        var lines: [String] = ["\(title) — \(subtitle)", ""]
        for section in sections {
            lines.append(section.title)
            for row in section.rows {
                let keys = row.keys.padding(toLength: 12, withPad: " ", startingAt: 0)
                lines.append("  \(keys)  \(row.blurb)")
            }
            lines.append("")
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Styled body for the help panel.
    @MainActor
    public static func attributedText() -> NSAttributedString {
        let titleFont = RoobytesFont.regular(size: 16)
        let captionFont = RoobytesFont.regular(size: 11)
        let sectionFont = RoobytesFont.bold(size: 11)
        let rowFont = RoobytesFont.regular(size: 12.5)
        let result = NSMutableAttributedString()

        let titlePara = NSMutableParagraphStyle()
        titlePara.paragraphSpacing = 1

        result.append(NSAttributedString(
            string: title + "\n",
            attributes: [
                .font: titleFont,
                .foregroundColor: RoobytesAccent.bright,
                .paragraphStyle: titlePara,
            ]
        ))

        let captionPara = NSMutableParagraphStyle()
        captionPara.paragraphSpacing = 8

        result.append(NSAttributedString(
            string: subtitle + "\n",
            attributes: [
                .font: captionFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: captionPara,
            ]
        ))

        let sectionPara = NSMutableParagraphStyle()
        sectionPara.paragraphSpacingBefore = 12
        sectionPara.paragraphSpacing = 4

        let rowPara = NSMutableParagraphStyle()
        rowPara.tabStops = [
            NSTextTab(textAlignment: .left, location: 124, options: [:]),
        ]
        rowPara.defaultTabInterval = 124
        rowPara.lineSpacing = 3
        rowPara.paragraphSpacing = 1

        for section in sections {
            result.append(NSAttributedString(
                string: section.title.uppercased() + "\n",
                attributes: [
                    .font: sectionFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .kern: 0.9,
                    .paragraphStyle: sectionPara,
                ]
            ))
            for row in section.rows {
                let line = NSMutableAttributedString()
                line.append(NSAttributedString(
                    string: row.keys,
                    attributes: [
                        .font: rowFont,
                        .foregroundColor: RoobytesAccent.bright,
                        .paragraphStyle: rowPara,
                    ]
                ))
                line.append(NSAttributedString(
                    string: "\t" + row.blurb + "\n",
                    attributes: [
                        .font: rowFont,
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: rowPara,
                    ]
                ))
                result.append(line)
            }
        }

        return result
    }

    /// Lines for layout / tests.
    public static var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

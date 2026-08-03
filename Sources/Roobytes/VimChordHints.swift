import Foundation

/// Context-aware second-stroke hints for pending Normal chords (`g`, `r`, `z`, …).
public enum VimChordHints {
    public struct Context: Sendable {
        public var hasURLUnderCaret: Bool
        public var canToggleFocus: Bool
        public var canMarkTaskDone: Bool
        public var canMarkTaskOpen: Bool
        public var hasFocusTask: Bool
        public var canFold: Bool
        public var isFolded: Bool

        public init(
            hasURLUnderCaret: Bool = false,
            canToggleFocus: Bool = false,
            canMarkTaskDone: Bool = false,
            canMarkTaskOpen: Bool = false,
            hasFocusTask: Bool = false,
            canFold: Bool = false,
            isFolded: Bool = false
        ) {
            self.hasURLUnderCaret = hasURLUnderCaret
            self.canToggleFocus = canToggleFocus
            self.canMarkTaskDone = canMarkTaskDone
            self.canMarkTaskOpen = canMarkTaskOpen
            self.hasFocusTask = hasFocusTask
            self.canFold = canFold
            self.isFolded = isFolded
        }
    }

    public struct Entry: Equatable, Sendable {
        public var keys: String
        public var blurb: String
    }

    /// Multiline palette body for a pending first key (+ optional count).
    public static func display(pending: Character, count: Int, context: Context) -> String {
        let entries = entries(for: pending, context: context)
        let head: String
        if count > 0 {
            head = "\(count)\(pending) · waiting"
        } else {
            head = "\(pending) · waiting"
        }
        guard !entries.isEmpty else { return head }
        let rows = entries.map { "  \($0.keys)  \($0.blurb)" }
        return ([head] + rows).joined(separator: "\n")
    }

    public static func entries(for pending: Character, context: Context) -> [Entry] {
        switch pending {
        case "g":
            var rows: [Entry] = [
                Entry(keys: "gg", blurb: "Top of file"),
                Entry(keys: "gj gk", blurb: "Down / up one wrapped row"),
            ]
            if context.hasURLUnderCaret {
                rows.append(Entry(keys: "gx", blurb: "Open URL in Firefox"))
                rows.append(Entry(keys: "gX", blurb: "Open URL · Private"))
            }
            return rows
        case "z":
            var rows: [Entry] = [
                Entry(keys: "z=", blurb: "Auto-fix spelling"),
                Entry(keys: "zz", blurb: "Center cursor line"),
            ]
            if context.canFold {
                rows.append(Entry(keys: "za", blurb: "Toggle fold"))
                if context.isFolded {
                    rows.append(Entry(keys: "zo", blurb: "Open fold"))
                } else {
                    rows.append(Entry(keys: "zc", blurb: "Close fold"))
                }
            }
            return rows
        case "d":
            return [Entry(keys: "dd", blurb: "Delete line")]
        case "y":
            return [Entry(keys: "yy", blurb: "Yank line content")]
        case "r":
            return [Entry(keys: "r{char}", blurb: "Replace under caret")]
        case "m":
            return [
                Entry(
                    keys: "md",
                    blurb: context.canMarkTaskDone ? "Mark done [x]" : "Mark done (need open task)"
                ),
                Entry(
                    keys: "mD",
                    blurb: context.canMarkTaskOpen ? "Mark open [ ]" : "Mark open (need done task)"
                ),
                Entry(
                    keys: "mf",
                    blurb: context.canToggleFocus ? "Toggle focus [!]" : "Focus (open task only)"
                ),
            ]
        case "'":
            if context.hasFocusTask {
                return [Entry(keys: "'f", blurb: "Jump to focus")]
            }
            return [Entry(keys: "'f", blurb: "Jump to focus (none yet)")]
        case "]":
            return [Entry(keys: "]t", blurb: "Next undone task")]
        case "[":
            return [Entry(keys: "[t", blurb: "Previous undone task")]
        default:
            return []
        }
    }
}

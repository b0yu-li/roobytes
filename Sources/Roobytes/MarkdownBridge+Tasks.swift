import Foundation

// MARK: - Task state helpers

extension MarkdownBridge {
    /// Index of the single `[!]` focused task line, if any.
    public static func focusTaskLineIndex(in lines: [String]) -> Int? {
        for (index, line) in lines.enumerated() where taskState(in: line) == .focused {
            return index
        }
        return nil
    }

    public static func focusTaskLineIndex(inMarkdown markdown: String) -> Int? {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return focusTaskLineIndex(in: lines)
    }

    /// Lines with an undone task (`[ ]` or `[!]`). Done / deprecated are excluded.
    public static func undoneTaskLineIndices(in lines: [String]) -> [Int] {
        lines.indices.filter { idx in
            switch taskState(in: lines[idx]) {
            case .open, .focused: return true
            default: return false
            }
        }
    }

    /// Next undone task hopping `count` steps below `from` (exclusive of `from`).
    public static func nextUndoneTaskLine(from line: Int, count: Int = 1, in lines: [String]) -> Int? {
        let hops = max(1, count)
        let undone = undoneTaskLineIndices(in: lines).filter { $0 > line }
        guard hops <= undone.count else { return nil }
        return undone[hops - 1]
    }

    /// Previous undone task hopping `count` steps above `from` (exclusive of `from`).
    public static func previousUndoneTaskLine(from line: Int, count: Int = 1, in lines: [String]) -> Int? {
        let hops = max(1, count)
        let undone = undoneTaskLineIndices(in: lines).filter { $0 < line }
        guard hops <= undone.count else { return nil }
        return undone[undone.count - hops]
    }

    /// Task marker state for a markdown line; `nil` if not a task.
    static func taskState(in line: String) -> TaskMarkerState? {
        let (_, rest) = splitIndent(line)
        return matchTask(rest)?.state
    }

    /// `true` / `false` for done vs open; `nil` if not a task. Deprecated / focused are not "done".
    static func taskCheckedState(in line: String) -> Bool? {
        guard let state = taskState(in: line) else { return nil }
        switch state {
        case .open, .focused, .deprecated: return false
        case .done: return true
        }
    }

    /// Cycle `[ ]` / `[!]` → `[x]` → `[~]` → `[ ]`. Returns nil if not a task.
    static func toggleTaskMarker(in line: String) -> String? {
        let (indent, rest) = splitIndent(line)
        guard matchTask(rest) != nil else { return nil }
        var newRest = rest
        let cycle: [(String, String)] = [
            ("[~]", "[ ]"),
            ("[x]", "[~]"), ("[X]", "[~]"),
            ("[!]", "[x]"),
            ("[ ]", "[x]"),
        ]
        for (from, to) in cycle {
            if let range = newRest.range(of: from) {
                newRest.replaceSubrange(range, with: to)
                return indent + newRest
            }
        }
        return nil
    }

    /// Force `[x]` (vim `md`). Nil if not a task or already done.
    public static func markTaskDone(in line: String) -> String? {
        guard let state = taskState(in: line), state != .done else { return nil }
        return replaceTaskBracket(in: line, with: "[x]")
    }

    /// Force `[ ]` (vim `mD`). Nil if not a task or already open.
    public static func markTaskOpen(in line: String) -> String? {
        guard let state = taskState(in: line), state != .open else { return nil }
        return replaceTaskBracket(in: line, with: "[ ]")
    }

    /// Focus toggle on one line: `[ ]` ↔ `[!]`. Nil if not an open/focused task.
    static func toggleFocusMarker(in line: String) -> String? {
        guard let state = taskState(in: line) else { return nil }
        switch state {
        case .focused:
            return replaceTaskBracket(in: line, with: "[ ]")
        case .open:
            return replaceTaskBracket(in: line, with: "[!]")
        case .done, .deprecated:
            return nil
        }
    }

    /// Demote `[!]` → `[ ]` (identity otherwise).
    static func clearFocusMarker(in line: String) -> String {
        guard taskState(in: line) == .focused else { return line }
        return replaceTaskBracket(in: line, with: "[ ]") ?? line
    }

    // MARK: - Parent / child task cascade

    /// Nearest task line above `lineIdx` with strictly lower indent level.
    /// Stops at the first line with lower indent — returns it only if it's a task.
    public static func parentTaskLineIndex(of lineIdx: Int, in lines: [String]) -> Int? {
        guard lineIdx > 0, lineIdx < lines.count else { return nil }
        let myLevel = lineIndentLevel(lines[lineIdx])
        guard myLevel > 0 else { return nil }
        for i in stride(from: lineIdx - 1, through: 0, by: -1) {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let level = lineIndentLevel(line)
            if level < myLevel {
                return taskState(in: line) != nil ? i : nil
            }
        }
        return nil
    }

    /// Direct child task line indices of a parent (shallowest task indent level within `childLineRange`).
    public static func directChildTaskLineIndices(of parentIdx: Int, in lines: [String]) -> [Int] {
        guard let range = childLineRange(parent: parentIdx, in: lines) else { return [] }
        let taskChildren = range.filter { idx in
            let line = lines[idx]
            return !line.trimmingCharacters(in: .whitespaces).isEmpty && taskState(in: line) != nil
        }
        guard let minLevel = taskChildren.map({ lineIndentLevel(lines[$0]) }).min() else { return [] }
        return taskChildren.filter { lineIndentLevel(lines[$0]) == minLevel }
    }

    /// Cascade parent task state upward after a child task changes (toggle / create / Esc sync).
    /// Marks parent done when all direct sub-tasks are resolved (done / deprecated);
    /// marks parent open when any direct sub-task is unresolved while parent is done.
    /// Returns indices of all parent lines that were modified.
    @discardableResult
    public static func cascadeParentTaskState(afterToggling toggledLine: Int, in lines: inout [String]) -> [Int] {
        var modified: [Int] = []
        var current = toggledLine
        while let parentIdx = parentTaskLineIndex(of: current, in: lines) {
            if let change = reconcileParentWithChildren(parentIdx, in: lines) {
                lines[parentIdx] = change
                modified.append(parentIdx)
                current = parentIdx
                continue
            }
            break
        }
        return modified
    }

    /// Keep `lineIdx` consistent with its direct children, then cascade ancestors.
    /// Use after creating/editing a task line, or after marking a parent done while kids remain open.
    @discardableResult
    public static func reconcileTaskTree(around lineIdx: Int, in lines: inout [String]) -> [Int] {
        var modified: [Int] = []
        if let change = reconcileParentWithChildren(lineIdx, in: lines) {
            lines[lineIdx] = change
            modified.append(lineIdx)
        }
        modified.append(contentsOf: cascadeParentTaskState(afterToggling: lineIdx, in: &lines))
        return modified
    }

    /// If `parentIdx` is a done task with any unresolved direct child, return the open form.
    /// If it is an open/focused task whose direct children are all resolved, return the done form.
    /// Otherwise `nil` (no change).
    private static func reconcileParentWithChildren(_ parentIdx: Int, in lines: [String]) -> String? {
        guard parentIdx >= 0, parentIdx < lines.count else { return nil }
        guard let parentState = taskState(in: lines[parentIdx]) else { return nil }
        let children = directChildTaskLineIndices(of: parentIdx, in: lines)
        guard !children.isEmpty else { return nil }
        let allResolved = children.allSatisfy {
            let s = taskState(in: lines[$0])
            return s == .done || s == .deprecated
        }
        if allResolved && parentState != .done {
            return markTaskDone(in: lines[parentIdx])
        }
        if !allResolved && parentState == .done {
            return markTaskOpen(in: lines[parentIdx])
        }
        return nil
    }

    private static func replaceTaskBracket(in line: String, with bracket: String) -> String? {
        let (indent, rest) = splitIndent(line)
        guard matchTask(rest) != nil else { return nil }
        var newRest = rest
        for from in ["[!]", "[~]", "[x]", "[X]", "[ ]"] {
            if let range = newRest.range(of: from) {
                newRest.replaceSubrange(range, with: bracket)
                return indent + newRest
            }
        }
        return nil
    }
}

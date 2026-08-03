import Foundation

// MARK: - Nested list folds (session view only)

extension MarkdownBridge {
    /// Indent level of a raw markdown line (2 spaces per level).
    static func lineIndentLevel(_ line: String) -> Int {
        let (indent, _) = splitIndent(line)
        return indentLevel(from: indent)
    }

    /// Consecutive lines after `parent` with indent strictly greater than the parent, until a
    /// non-empty line at indent ≤ parent (or EOF). Blank lines inside the nest are included.
    /// Returns `nil` when there are no children.
    public static func childLineRange(parent: Int, in lines: [String]) -> Range<Int>? {
        guard parent >= 0, parent < lines.count else { return nil }
        let parentLevel = lineIndentLevel(lines[parent])
        var end = parent + 1
        while end < lines.count {
            let line = lines[end]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                end += 1
                continue
            }
            if lineIndentLevel(line) <= parentLevel { break }
            end += 1
        }
        if end <= parent + 1 { return nil }
        return (parent + 1)..<end
    }

    public static func canFold(parent: Int, in lines: [String]) -> Bool {
        childLineRange(parent: parent, in: lines) != nil
    }

    public static func childCount(parent: Int, in lines: [String]) -> Int {
        childLineRange(parent: parent, in: lines)?.count ?? 0
    }

    /// Done (`[x]`) task lines that still have nestable children — candidates for `:folddone`.
    public static func foldableDoneTaskParents(in lines: [String]) -> Set<Int> {
        Set(lines.indices.filter { idx in
            taskState(in: lines[idx]) == .done && canFold(parent: idx, in: lines)
        })
    }

    /// Shift fold parent indices after inserting `count` lines at `at` (index of the first new line).
    public static func foldsAfterInserting(count: Int, at index: Int, into folds: Set<Int>) -> Set<Int> {
        guard count > 0, !folds.isEmpty else { return folds }
        return Set(folds.map { $0 >= index ? $0 + count : $0 })
    }

    /// Drop / shift fold parent indices after deleting `range` (half-open line indices).
    public static func foldsAfterDeleting(_ range: Range<Int>, from folds: Set<Int>) -> Set<Int> {
        guard !range.isEmpty, !folds.isEmpty else { return folds }
        let delta = range.count
        var next = Set<Int>()
        for parent in folds {
            if range.contains(parent) { continue }
            if parent >= range.upperBound {
                next.insert(parent - delta)
            } else {
                next.insert(parent)
            }
        }
        return next
    }

    /// Line indices hidden because they fall under a folded parent.
    /// Blank separator lines stay visible so folds don't leave a "swallowed" hole.
    public static func hiddenLineIndices(foldedParents: Set<Int>, lines: [String]) -> Set<Int> {
        var hidden = Set<Int>()
        for p in foldedParents {
            guard let range = childLineRange(parent: p, in: lines) else { continue }
            for idx in range {
                guard idx >= 0, idx < lines.count else { continue }
                if lines[idx].trimmingCharacters(in: .whitespaces).isEmpty { continue }
                hidden.insert(idx)
            }
        }
        return hidden
    }

    /// Source-line indices present in the attributed view (`mdSourceLine`).
    public static func visibleSourceLineIndices(in attributed: NSAttributedString) -> Set<Int> {
        var result = Set<Int>()
        let full = NSRange(location: 0, length: attributed.length)
        guard full.length > 0 else { return result }
        attributed.enumerateAttribute(.mdSourceLine, in: full, options: []) { value, _, _ in
            if let line = value as? Int {
                result.insert(line)
            }
        }
        return result
    }
}

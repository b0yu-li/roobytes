import Foundation

/// UTF-16 line-start offsets for O(log n) line-index lookups.
public struct LineIndexCache: Sendable {
    /// Character index of the start of each line (line 0 at 0).
    private(set) var starts: [Int] = [0]
    private var length: Int = 0
    /// Exact revision from caller snapshot. Callers increment when text storage changes.
    private var lastRevision: Int?

    public init() {}

    public mutating func rebuildForced(from string: String, revision: Int? = nil) {
        rebuildForced(from: string as NSString, revision: revision)
    }

    public mutating func rebuildForced(from ns: NSString, revision: Int? = nil) {
        if let revision, revision == lastRevision, !starts.isEmpty { return }
        lastRevision = revision
        length = ns.length
        var next: [Int] = [0]
        next.reserveCapacity(max(8, ns.length / 32 + 1))
        if ns.length > 0 {
            for i in 0..<ns.length where ns.character(at: i) == 10 {
                next.append(i + 1)
            }
            // A final `\n` makes AppKit show `extraLineFragment` with no glyphs. That start
            // equals `length` and must not count as a navigable / gutter line (vim: `"a\nb\n"`
            // is two lines, not three).
            if ns.character(at: ns.length - 1) == 10, next.count > 1, next.last == ns.length {
                next.removeLast()
            }
        }
        starts = next
    }

    public var lineCount: Int { max(1, starts.count) }

    /// 0-based line containing `characterIndex`.
    public func lineIndex(at characterIndex: Int) -> Int {
        guard !starts.isEmpty else { return 0 }
        let idx = max(0, min(characterIndex, max(0, length)))
        var lo = 0
        var hi = starts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= idx {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return max(0, lo - 1)
    }

    public func characterIndex(forLine line: Int) -> Int {
        guard !starts.isEmpty else { return 0 }
        let i = max(0, min(line, starts.count - 1))
        return starts[i]
    }
}

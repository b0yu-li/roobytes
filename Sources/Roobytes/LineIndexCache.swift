import Foundation

/// UTF-16 line-start offsets for O(log n) line-index lookups.
struct LineIndexCache: Sendable {
    /// Character index of the start of each line (line 0 at 0).
    private(set) var starts: [Int] = [0]
    private var length: Int = 0
    /// Exact revision from caller snapshot. Callers increment when text storage changes.
    private var lastRevision: Int?

    mutating func rebuildForced(from string: String, revision: Int? = nil) {
        rebuildForced(from: string as NSString, revision: revision)
    }

    mutating func rebuildForced(from ns: NSString, revision: Int? = nil) {
        if let revision, revision == lastRevision, !starts.isEmpty { return }
        lastRevision = revision
        length = ns.length
        var next: [Int] = [0]
        next.reserveCapacity(max(8, ns.length / 32 + 1))
        if ns.length > 0 {
            for i in 0..<ns.length where ns.character(at: i) == 10 {
                next.append(i + 1)
            }
        }
        starts = next
    }

    var lineCount: Int { max(1, starts.count) }

    /// 0-based line containing `characterIndex`.
    func lineIndex(at characterIndex: Int) -> Int {
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

    func characterIndex(forLine line: Int) -> Int {
        guard !starts.isEmpty else { return 0 }
        let i = max(0, min(line, starts.count - 1))
        return starts[i]
    }
}

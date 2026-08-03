import Foundation

/// Zoxide-style frecency history for opened notes.
@MainActor
public final class FileHistoryStore {
    public static let shared = FileHistoryStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "Roobytes.fileHistory.v1"
    private let maxEntries = 200
    /// Decay half-life in hours (~1 week).
    private let halfLifeHours: Double = 168

    private struct Entry: Codable {
        var openCount: Int
        var lastOpened: Date
    }

    private var entries: [String: Entry]

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    public func record(url: URL) {
        let path = url.standardizedFileURL.path
        var entry = entries[path] ?? Entry(openCount: 0, lastOpened: .distantPast)
        entry.openCount += 1
        entry.lastOpened = Date()
        entries[path] = entry
        trimIfNeeded()
        persist()
    }

    /// Score for a path; higher is better. Unknown paths score `0`.
    public func score(for url: URL, now: Date = Date()) -> Double {
        guard let entry = entries[url.standardizedFileURL.path] else { return 0 }
        return Self.frecency(openCount: entry.openCount, lastOpened: entry.lastOpened, now: now, halfLifeHours: halfLifeHours)
    }

    /// Sort vault files by frecency (desc), then alphabetical relative path.
    public func ranked(_ files: [URL], vault: URL, now: Date = Date()) -> [URL] {
        files.sorted { a, b in
            let sa = score(for: a, now: now)
            let sb = score(for: b, now: now)
            if sa != sb { return sa > sb }
            let da = VaultFileIndex.relativeDisplayPath(for: a, vault: vault)
            let db = VaultFileIndex.relativeDisplayPath(for: b, vault: vault)
            return da.localizedCaseInsensitiveCompare(db) == .orderedAscending
        }
    }

    public static func frecency(
        openCount: Int,
        lastOpened: Date,
        now: Date,
        halfLifeHours: Double
    ) -> Double {
        let hours = max(0, now.timeIntervalSince(lastOpened) / 3600)
        let decay = pow(0.25, hours / halfLifeHours)
        return Double(openCount) * decay
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        let sorted = entries.sorted { a, b in
            let sa = Self.frecency(
                openCount: a.value.openCount,
                lastOpened: a.value.lastOpened,
                now: Date(),
                halfLifeHours: halfLifeHours
            )
            let sb = Self.frecency(
                openCount: b.value.openCount,
                lastOpened: b.value.lastOpened,
                now: Date(),
                halfLifeHours: halfLifeHours
            )
            return sa > sb
        }
        entries = Dictionary(uniqueKeysWithValues: sorted.prefix(maxEntries).map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

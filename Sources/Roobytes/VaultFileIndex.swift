import Foundation

/// Recursive markdown file listing under a vault folder.
public enum VaultFileIndex {
    /// Precomputed vault entry (url + display path) for ⌘P ranking without re-deriving paths.
    public struct Entry: Sendable {
        public let url: URL
        public let displayPath: String
    }

    /// Markdown / text notes under `root`, skipping hidden path components (dot-directories).
    /// Sorted by vault-relative path (case-insensitive).
    @MainActor
    public static func scan(root: URL) -> [URL] {
        scanEntries(root: root).map(\.url)
    }

    /// Same as `scan`, but keeps display paths for frecency / fuzzy without recomputing.
    @MainActor
    public static func scanEntries(root: URL) -> [Entry] {
        let fm = FileManager.default
        let rootStd = root.standardizedFileURL
        let rootPath = rootStd.path
        guard let enumerator = fm.enumerator(
            at: rootStd,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [Entry] = []
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            let relativeComponents = standardized.path
                .dropFirst(rootPrefix.count)
                .split(separator: "/")
                .map(String.init)
            if relativeComponents.contains(where: { $0.hasPrefix(".") }) {
                if let values = try? standardized.resourceValues(forKeys: [.isDirectoryKey]),
                   values.isDirectory == true
                {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard let values = try? standardized.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]),
                  values.isDirectory != true,
                  values.isRegularFile == true
            else { continue }
            guard isMarkdownPath(standardized) else { continue }
            guard standardized.path.hasPrefix(rootPrefix) else { continue }
            let display = relativeDisplayPath(for: standardized, vault: rootStd)
            results.append(Entry(url: standardized, displayPath: display))
        }

        return results.sorted {
            $0.displayPath.localizedCaseInsensitiveCompare($1.displayPath) == .orderedAscending
        }
    }

    /// Vault-relative path without markdown extension (e.g. `diaries/2026-07-20`, `Gaps`).
    public static func relativeDisplayPath(for url: URL, vault: URL) -> String {
        let file = url.standardizedFileURL
        let root = vault.standardizedFileURL
        let relative: String
        if file.path.hasPrefix(root.path) {
            var rel = String(file.path.dropFirst(root.path.count))
            if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            relative = rel.isEmpty ? file.lastPathComponent : rel
        } else {
            relative = file.lastPathComponent
        }
        return stripMarkdownExtension(relative)
    }

    public static func stripMarkdownExtension(_ name: String) -> String {
        let lower = name.lowercased()
        for ext in [".markdown", ".mdown", ".mkd", ".md"] where lower.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            return String(name[..<dot])
        }
        return name
    }

    private static func isMarkdownPath(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "txt"].contains(ext)
    }
}

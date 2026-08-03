import Foundation

/// Recursive markdown file listing under a vault folder.
public enum VaultFileIndex {
    /// Markdown / text notes under `root`, skipping hidden path components (dot-directories).
    /// Sorted by vault-relative path (case-insensitive).
    @MainActor
    public static func scan(root: URL) -> [URL] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            // Extra guard: skip any path component that starts with `.`
            let relativeComponents = standardized.path
                .dropFirst(rootPrefix.count)
                .split(separator: "/")
                .map(String.init)
            if relativeComponents.contains(where: { $0.hasPrefix(".") }) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: standardized.path, isDirectory: &isDir), isDir.boolValue {
                    enumerator.skipDescendants()
                }
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            guard isMarkdownPath(standardized) else { continue }
            guard standardized.path.hasPrefix(rootPrefix) else { continue }
            results.append(standardized)
        }

        return results.sorted {
            relativeDisplayPath(for: $0, vault: root)
                .localizedCaseInsensitiveCompare(relativeDisplayPath(for: $1, vault: root))
                == .orderedAscending
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

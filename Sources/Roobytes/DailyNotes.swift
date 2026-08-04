import Foundation

/// Daily note paths and create-from-template for the vault’s `diaries/` folder.
/// Template path is vault-root `daily-notes-temp.md` (Create starter / Choose file via setup UI).
public enum DailyNotes {
    public static let templateFileName = "daily-notes-temp.md"
    public static let diariesFolderName = "diaries"

    /// Default body written by “Create starter template”.
    public static let starterTemplateMarkdown = """
    ## Focus
    + [ ]

    ## Notes

    """

    public enum EnsureError: Error, Equatable, Sendable {
        case templateMissing
        case writeFailed(String)
    }

    /// `YYYY-MM-DD.md` for the given date in `calendar` (local by default).
    public static func fileName(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d.md", y, m, d)
    }

    /// Date stem without extension (`2026-07-28`).
    public static func dateStem(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let name = fileName(for: date, calendar: calendar)
        return String(name.dropLast(3)) // ".md"
    }

    public static func templateURL(vault: URL) -> URL {
        vault.appendingPathComponent(templateFileName, isDirectory: false)
    }

    public static func diariesFolder(vault: URL) -> URL {
        vault.appendingPathComponent(diariesFolderName, isDirectory: true)
    }

    public static func templateExists(
        vault: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: templateURL(vault: vault).path)
    }

    /// Write the starter markdown to the vault-root template path (overwrites if present).
    public static func installStarterTemplate(
        vault: URL,
        fileManager: FileManager = .default
    ) throws {
        let dest = templateURL(vault: vault)
        do {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try starterTemplateMarkdown.write(to: dest, atomically: true, encoding: .utf8)
        } catch {
            throw EnsureError.writeFailed(error.localizedDescription)
        }
    }

    /// Copy `source` into the vault-root template path (overwrites if present).
    public static func installTemplate(
        copying source: URL,
        vault: URL,
        fileManager: FileManager = .default
    ) throws {
        let dest = templateURL(vault: vault)
        do {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: source, to: dest)
        } catch {
            throw EnsureError.writeFailed(error.localizedDescription)
        }
    }

    /// Prefer exact `YYYY-MM-DD.md`, else any `YYYY-MM-DD*.md` in `diaries/`.
    public static func existingNoteURL(
        vault: URL,
        date: Date = Date(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) -> URL? {
        let folder = diariesFolder(vault: vault)
        let exact = folder.appendingPathComponent(fileName(for: date, calendar: calendar))
        if fileManager.fileExists(atPath: exact.path) {
            return exact.standardizedFileURL
        }

        let stem = dateStem(for: date, calendar: calendar)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let matches = contents
            .filter { url in
                let name = url.lastPathComponent
                let ext = url.pathExtension.lowercased()
                guard ["md", "markdown", "txt"].contains(ext) else { return false }
                return name.hasPrefix(stem)
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        return matches.first?.standardizedFileURL
    }

    /// Open existing daily note, or create `diaries/YYYY-MM-DD.md` from the vault template.
    public static func ensureTodaysNote(
        vault: URL,
        date: Date = Date(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        if let existing = existingNoteURL(
            vault: vault,
            date: date,
            calendar: calendar,
            fileManager: fileManager
        ) {
            return existing
        }

        guard templateExists(vault: vault, fileManager: fileManager) else {
            throw EnsureError.templateMissing
        }

        let folder = diariesFolder(vault: vault)
        if !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw EnsureError.writeFailed(error.localizedDescription)
            }
        }

        let destination = folder.appendingPathComponent(fileName(for: date, calendar: calendar))
        do {
            try fileManager.copyItem(at: templateURL(vault: vault), to: destination)
        } catch {
            throw EnsureError.writeFailed(error.localizedDescription)
        }
        return destination.standardizedFileURL
    }
}

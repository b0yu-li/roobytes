import Foundation
import OSLog

/// Lightweight troubleshooting log (vim chords, newlines). Off by default — Settings → Debug logging.
enum RoobytesDebugLog {
    private static let logger = Logger(subsystem: "dev.roobytes.app", category: "debug")
    static let defaultsKey = "Roobytes.debugLogging"
    private static let fileName = "debug.log"
    private static let maxFileBytes = 512 * 1024

    /// Same key as `RoobytesSettings.debugLogging` (readable without hopping to MainActor).
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Directory: `~/Library/Logs/Roobytes/`.
    static var logDirectoryURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Roobytes", isDirectory: true)
    }

    static var logFileURL: URL {
        logDirectoryURL.appendingPathComponent(fileName)
    }

    static func event(_ message: String) {
        guard isEnabled else { return }
        write("\(timestamp())  \(message)", alsoOSLog: .debug)
    }

    /// Call when the setting flips so the file starts/ends with a clear marker.
    static func noteEnabledChanged(_ enabled: Bool) {
        write("\(timestamp())  debugLogging=\(enabled ? "on" : "off")", alsoOSLog: .notice)
    }

    private enum OSLogLevel {
        case debug
        case notice
    }

    private static func write(_ line: String, alsoOSLog level: OSLogLevel) {
        switch level {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .notice:
            logger.notice("\(line, privacy: .public)")
        }
        appendToFile(line)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    private static func appendToFile(_ line: String) {
        let dir = logDirectoryURL
        let file = logFileURL
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? NSNumber,
               size.intValue > maxFileBytes
            {
                try? FileManager.default.removeItem(at: file)
            }
            let data = (line + "\n").data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file, options: .atomic)
            }
        } catch {
            logger.error("log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

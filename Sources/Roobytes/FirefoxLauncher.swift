import AppKit

/// Open a URL in the user's preferred browser, with Firefox private-window support.
public enum BrowserLauncher {
    public enum LaunchError: Error, Equatable {
        case openFailed
    }

    /// Open `url` using the system default browser.
    /// When `privateBrowsing` is true and Firefox is available, opens a Firefox private window;
    /// otherwise falls back to the default browser (private mode not guaranteed).
    @discardableResult
    public static func open(_ url: URL, privateBrowsing: Bool) -> Result<Void, LaunchError> {
        if privateBrowsing, let firefox = firefoxAppURL() {
            return runOpen(arguments: ["-na", firefox.path, "--args", "-private-window", url.absoluteString])
        }
        if NSWorkspace.shared.open(url) {
            return .success(())
        }
        return .failure(.openFailed)
    }

    private static let firefoxCandidates: [URL] = [
        URL(fileURLWithPath: "/Applications/Firefox.app"),
        URL(fileURLWithPath: "/Applications/Firefox Developer Edition.app"),
    ]

    private static func firefoxAppURL() -> URL? {
        firefoxCandidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func runOpen(arguments: [String]) -> Result<Void, LaunchError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
            return .success(())
        } catch {
            return .failure(.openFailed)
        }
    }
}

/// Legacy name — callers can still reference `FirefoxLauncher`.
public typealias FirefoxLauncher = BrowserLauncher

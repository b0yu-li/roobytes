import AppKit
import Foundation

extension Notification.Name {
    static let roobytesAppearanceDidChange = Notification.Name("Roobytes.appearanceDidChange")
    static let roobytesWordCompletionDidChange = Notification.Name("Roobytes.wordCompletionDidChange")
    static let roobytesSpellCheckingDidChange = Notification.Name("Roobytes.spellCheckingDidChange")
}

enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// UserDefaults keys shared with non-MainActor readers (`MarkdownBridge`, `RoobytesAccent`, debug log).
enum RoobytesDefaultsKey {
    static let reopenLastFileOnLaunch = "Roobytes.reopenLastFileOnLaunch"
    static let restorePinOnLaunch = "Roobytes.restorePinOnLaunch"
    static let lastFolderPath = "Roobytes.lastFolderPath"
    static let lastFilePath = "Roobytes.lastFilePath"
    static let isPinned = "Roobytes.isPinned"
    static let appearance = "Roobytes.appearance"
    static let accent = "Roobytes.accent"
    static let debugLogging = RoobytesDebugLog.defaultsKey
    static let typewriterSound = "Roobytes.typewriterSound"
    static let tipsOnStartup = "Roobytes.tipsOnStartup"
    static let lastTipID = "Roobytes.lastTipID"
    static let wordCompletion = "Roobytes.wordCompletion"
    static let spellChecking = "Roobytes.spellChecking"
}

/// Persisted user preferences (UserDefaults).
@MainActor
final class RoobytesSettings {
    static let shared = RoobytesSettings()

    private let defaults = UserDefaults.standard

    /// When true (default), launch opens the last edited note if it still exists.
    var reopenLastFileOnLaunch: Bool {
        get {
            if defaults.object(forKey: RoobytesDefaultsKey.reopenLastFileOnLaunch) == nil { return true }
            return defaults.bool(forKey: RoobytesDefaultsKey.reopenLastFileOnLaunch)
        }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.reopenLastFileOnLaunch) }
    }

    /// When true (default), restore the float-on-top pin from the last session.
    var restorePinOnLaunch: Bool {
        get {
            if defaults.object(forKey: RoobytesDefaultsKey.restorePinOnLaunch) == nil { return true }
            return defaults.bool(forKey: RoobytesDefaultsKey.restorePinOnLaunch)
        }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.restorePinOnLaunch) }
    }

    /// When true, append vim / newline breadcrumbs to `~/Library/Logs/Roobytes/debug.log`. Default off.
    var debugLogging: Bool {
        get { defaults.bool(forKey: RoobytesDefaultsKey.debugLogging) }
        set {
            defaults.set(newValue, forKey: RoobytesDefaultsKey.debugLogging)
            RoobytesDebugLog.noteEnabledChanged(newValue)
        }
    }

    /// When true, play soft sound effects (typing, motions, `:w`, task done). Default off.
    var typewriterSound: Bool {
        get { defaults.bool(forKey: RoobytesDefaultsKey.typewriterSound) }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.typewriterSound) }
    }

    /// When true (default), show a random tip shortly after launch.
    var tipsOnStartup: Bool {
        get {
            if defaults.object(forKey: RoobytesDefaultsKey.tipsOnStartup) == nil { return true }
            return defaults.bool(forKey: RoobytesDefaultsKey.tipsOnStartup)
        }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.tipsOnStartup) }
    }

    /// When true (default), Insert-mode buffer word completion (menu + ghost).
    var wordCompletion: Bool {
        get {
            if defaults.object(forKey: RoobytesDefaultsKey.wordCompletion) == nil { return true }
            return defaults.bool(forKey: RoobytesDefaultsKey.wordCompletion)
        }
        set {
            defaults.set(newValue, forKey: RoobytesDefaultsKey.wordCompletion)
            NotificationCenter.default.post(name: .roobytesWordCompletionDidChange, object: nil)
        }
    }

    /// When true (default), underline likely misspellings on the Insert-mode active line.
    var spellChecking: Bool {
        get {
            if defaults.object(forKey: RoobytesDefaultsKey.spellChecking) == nil { return true }
            return defaults.bool(forKey: RoobytesDefaultsKey.spellChecking)
        }
        set {
            defaults.set(newValue, forKey: RoobytesDefaultsKey.spellChecking)
            NotificationCenter.default.post(name: .roobytesSpellCheckingDidChange, object: nil)
        }
    }

    /// Last tip id shown — used to avoid immediate repeats.
    var lastTipID: String? {
        get { defaults.string(forKey: RoobytesDefaultsKey.lastTipID) }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.lastTipID) }
    }

    var isPinned: Bool {
        get { defaults.bool(forKey: RoobytesDefaultsKey.isPinned) }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.isPinned) }
    }

    /// System / Light / Dark. Default follows macOS.
    var appearance: AppearancePreference {
        get {
            guard let raw = defaults.string(forKey: RoobytesDefaultsKey.appearance),
                  let value = AppearancePreference(rawValue: raw)
            else { return .system }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: RoobytesDefaultsKey.appearance)
        }
    }

    /// Caret / pin / todo / code accent. Default gold.
    var accent: AccentPreference {
        get {
            AccentPreference.fromPersistedRawValue(
                defaults.string(forKey: RoobytesDefaultsKey.accent)
            ) ?? .gold
        }
        set {
            defaults.set(newValue.rawValue, forKey: RoobytesDefaultsKey.accent)
        }
    }

    var lastFolderPath: String? {
        get { defaults.string(forKey: RoobytesDefaultsKey.lastFolderPath) }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.lastFolderPath) }
    }

    var lastFilePath: String? {
        get { defaults.string(forKey: RoobytesDefaultsKey.lastFilePath) }
        set { defaults.set(newValue, forKey: RoobytesDefaultsKey.lastFilePath) }
    }

    var lastFolderURL: URL? {
        guard let path = lastFolderPath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue
        else { return nil }
        return url
    }

    var lastFileURL: URL? {
        guard let path = lastFilePath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Record the active note / vault for next launch.
    func rememberOpened(file: URL?, folder: URL?) {
        if let folder {
            lastFolderPath = folder.standardizedFileURL.path
        }
        if let file {
            lastFilePath = file.standardizedFileURL.path
            if folder == nil {
                lastFolderPath = file.deletingLastPathComponent().standardizedFileURL.path
            }
        }
    }

    func clearLastOpened() {
        lastFilePath = nil
        lastFolderPath = nil
    }
}

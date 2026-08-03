import AppKit

extension Notification.Name {
    static let roobytesAccentDidChange = Notification.Name("Roobytes.accentDidChange")
}

/// User-selectable accent presets. Each has a primary fill and a brighter
/// supplementary color for location feedback.
enum AccentPreference: String, CaseIterable, Sendable {
    case gold
    case coral
    case blue
    case purple
    case orange
    case green

    var title: String {
        switch self {
        case .gold: return "Gold"
        case .coral: return "Coral"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .green: return "Green"
        }
    }

    var color: NSColor {
        switch self {
        case .gold:
            return NSColor(calibratedRed: 0.72, green: 0.54, blue: 0.20, alpha: 1)
        case .coral:
            return NSColor(calibratedRed: 0.86, green: 0.38, blue: 0.40, alpha: 1)
        case .blue:
            return NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.86, alpha: 1)
        case .purple:
            return NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.82, alpha: 1)
        case .orange:
            return NSColor(calibratedRed: 0.90, green: 0.48, blue: 0.18, alpha: 1)
        case .green:
            return NSColor(calibratedRed: 0.22, green: 0.62, blue: 0.38, alpha: 1)
        }
    }

    /// Brighter companion for small glyphs / inline code on dark backgrounds.
    var bright: NSColor {
        switch self {
        case .gold:
            return NSColor(calibratedRed: 0.94, green: 0.78, blue: 0.37, alpha: 1)
        case .coral:
            return NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.55, alpha: 1)
        case .blue:
            return NSColor(calibratedRed: 0.45, green: 0.70, blue: 1.00, alpha: 1)
        case .purple:
            return NSColor(calibratedRed: 0.75, green: 0.58, blue: 1.00, alpha: 1)
        case .orange:
            return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.35, alpha: 1)
        case .green:
            return NSColor(calibratedRed: 0.40, green: 0.82, blue: 0.55, alpha: 1)
        }
    }

    /// Preserve the original first-preset value after replacing Teal with Gold.
    static func fromPersistedRawValue(_ raw: String?) -> AccentPreference? {
        if raw == "teal" { return .gold }
        guard let raw else { return nil }
        return AccentPreference(rawValue: raw)
    }
}

/// Shared Roobytes accent — reads the preference key directly so MarkdownBridge can stay nonisolated.
enum RoobytesAccent {
    static var preference: AccentPreference {
        AccentPreference.fromPersistedRawValue(
            UserDefaults.standard.string(forKey: RoobytesDefaultsKey.accent)
        ) ?? .gold
    }

    static var color: NSColor { preference.color }
    static var bright: NSColor { preference.bright }
    /// Supplementary accent for “you are here”: caret, selection, and mode state.
    static var caret: NSColor { preference.bright }
    /// Inverse glyph shown inside the Normal-mode block caret.
    static var caretForeground: NSColor {
        preference == .gold
            ? NSColor(calibratedWhite: 0.12, alpha: 1)
            : NSColor.white
    }

    static var codeBackground: NSColor {
        // Readable chip — still quieter than focus wash (0.32).
        color.withAlphaComponent(0.28)
    }

    static var codeForeground: NSColor {
        bright
    }

    /// Inline / bare URL highlight (accent companion — readable on dark canvas).
    static var linkForeground: NSColor { bright }

    /// `#tag` highlight — same accent family as links, no underline.
    static var tagForeground: NSColor { bright }

    /// `##` heading — strongest accent of the h2–h4 ladder.
    static var heading2Foreground: NSColor { bright }

    /// `###` heading — deeper base accent (distinct from bright h2).
    static var heading3Foreground: NSColor { color }

    /// `####` heading — soft accent mix toward secondary (quietest of the three).
    static var heading4Foreground: NSColor {
        mix(bright, RoobytesTheme.editorSecondary, t: 0.42)
    }

    /// Stronger than code chips so the focused task line reads first.
    static var focusWash: NSColor {
        color.withAlphaComponent(0.32)
    }

    static var selectionAttributes: [NSAttributedString.Key: Any] {
        [
            .backgroundColor: caret,
            .foregroundColor: caretForeground,
        ]
    }

    private static func mix(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let t = min(1, max(0, t))
        let ac = a.usingColorSpace(.deviceRGB) ?? a
        let bc = b.usingColorSpace(.deviceRGB) ?? b
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ac.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        bc.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return NSColor(
            calibratedRed: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: 1
        )
    }
}

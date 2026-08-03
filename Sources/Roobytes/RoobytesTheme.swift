import AppKit

/// Editor palette tuned for long reading — soft paper in light, lifted charcoal in dark.
/// Avoids pure white / pure black glare while keeping contrast readable.
public enum RoobytesTheme {
    /// Primary body / heading text.
    public static var editorForeground: NSColor {
        NSColor(name: "Roobytes.editorForeground") { appearance in
            if Self.isDark(appearance) {
                // ~#C4C6CA — soft gray, below system label white.
                return NSColor(calibratedRed: 0.77, green: 0.78, blue: 0.79, alpha: 1)
            }
            // ~#2E2F32 — ink, not pure black.
            return NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        }
    }

    /// De-emphasized runs (quotes, markers, focus-dim) in the editor.
    public static var editorSecondary: NSColor {
        NSColor(name: "Roobytes.editorSecondary") { appearance in
            if Self.isDark(appearance) {
                return NSColor(calibratedRed: 0.54, green: 0.55, blue: 0.58, alpha: 1)
            }
            // ~#6B6E74
            return NSColor(calibratedRed: 0.42, green: 0.43, blue: 0.45, alpha: 1)
        }
    }

    /// Quietest editor chrome (fold cues, fence ticks, thematic breaks).
    public static var editorTertiary: NSColor {
        NSColor(name: "Roobytes.editorTertiary") { appearance in
            if Self.isDark(appearance) {
                return NSColor(calibratedRed: 0.40, green: 0.41, blue: 0.44, alpha: 1)
            }
            // ~#9A9DA3
            return NSColor(calibratedRed: 0.60, green: 0.62, blue: 0.64, alpha: 1)
        }
    }

    /// Editor canvas — eye-friendly paper / charcoal (not system white / OLED black).
    public static var editorBackground: NSColor {
        NSColor(name: "Roobytes.editorBackground") { appearance in
            if Self.isDark(appearance) {
                // ~#1E1F23 — lifted cool charcoal; softer than pure black.
                return NSColor(calibratedRed: 0.118, green: 0.122, blue: 0.137, alpha: 1)
            }
            // ~#F3F3F2 — cool-neutral paper; cuts glare vs pure white.
            return NSColor(calibratedRed: 0.953, green: 0.953, blue: 0.949, alpha: 1)
        }
    }

    /// Relative gutter count for lines below the caret (`j` / `Nj`).
    public static var gutterJumpDown: NSColor {
        // Track accent so the “forward” jump reads as the product color.
        RoobytesAccent.bright
    }

    /// Relative gutter count for lines above the caret (`k` / `Nk`) — cool, distinct from accent.
    public static var gutterJumpUp: NSColor {
        NSColor(name: "Roobytes.gutterJumpUp") { appearance in
            if Self.isDark(appearance) {
                return NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.78, alpha: 1)
            }
            return NSColor(calibratedRed: 0.38, green: 0.45, blue: 0.62, alpha: 1)
        }
    }

    /// Absolute number on the caret line.
    public static var gutterCurrentLine: NSColor {
        NSColor(name: "Roobytes.gutterCurrentLine") { appearance in
            if Self.isDark(appearance) {
                return NSColor(calibratedRed: 0.70, green: 0.72, blue: 0.75, alpha: 1)
            }
            return NSColor(calibratedRed: 0.42, green: 0.43, blue: 0.46, alpha: 1)
        }
    }

    /// Whether `appearance` resolves to dark Aqua (or a dark variant).
    public static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

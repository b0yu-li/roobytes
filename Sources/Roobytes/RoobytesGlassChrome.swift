import AppKit

/// Shared frosted-glass chrome for floating HUDs (command palette, chord hints, file switcher).
///
/// Uses `NSVisualEffectView` only — system blur, no CIFilter / custom shaders — so cost stays
/// low and only while the panel is visible.
@MainActor
public enum RoobytesGlassChrome {
    public enum Style {
        /// `:` command input.
        case quiet
        /// Chord hints / file switcher / tips.
        case panel
        /// Flash messages (`Written`, etc.).
        case flash
        /// `:h` reference — denser so editor text doesn’t bleed through.
        case help
    }

    public static let highlightHeight: CGFloat = 1.0
    public static let cornerRadius: CGFloat = 12

    public static func makeHighlightView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        return view
    }

    public static func apply(
        shell: NSView,
        glass: NSVisualEffectView,
        tint: NSView,
        highlight: NSView? = nil,
        style: Style
    ) {
        let dark = RoobytesTheme.isDark(glass.effectiveAppearance)

        // Help uses a denser HUD material; other HUDs stay light frost.
        if style == .help {
            glass.material = .hudWindow
            glass.isEmphasized = true
        } else {
            // `.popover` / `.menu` read much more translucent than `.hudWindow` with
            // within-window blending — editor text stays visible under the frost.
            glass.material = .popover
            glass.isEmphasized = false
        }
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true

        let borderWidth: CGFloat
        let accentBorderAlpha: CGFloat
        let tintAlpha: CGFloat
        let highlightAlpha: CGFloat
        let shadowOpacity: Float
        let shadowRadius: CGFloat

        switch style {
        case .quiet:
            borderWidth = 1
            accentBorderAlpha = 0.50
            tintAlpha = dark ? 0.10 : 0.06
            highlightAlpha = dark ? 0.14 : 0.28
            shadowOpacity = 0.22
            shadowRadius = 14
        case .panel:
            borderWidth = 1.25
            accentBorderAlpha = 0.62
            tintAlpha = dark ? 0.12 : 0.07
            highlightAlpha = dark ? 0.16 : 0.32
            shadowOpacity = 0.28
            shadowRadius = 18
        case .flash:
            borderWidth = 1.5
            accentBorderAlpha = 0.82
            tintAlpha = dark ? 0.16 : 0.10
            highlightAlpha = dark ? 0.20 : 0.38
            shadowOpacity = 0.36
            shadowRadius = 20
        case .help:
            borderWidth = 1.25
            accentBorderAlpha = 0.70
            tintAlpha = dark ? 0.42 : 0.22
            highlightAlpha = dark ? 0.18 : 0.36
            shadowOpacity = 0.40
            shadowRadius = 24
        }

        shell.wantsLayer = true
        shell.layer?.backgroundColor = NSColor.clear.cgColor
        shell.layer?.masksToBounds = false
        shell.layer?.shadowColor = RoobytesAccent.color.cgColor
        shell.layer?.shadowOpacity = shadowOpacity
        shell.layer?.shadowRadius = shadowRadius
        shell.layer?.shadowOffset = CGSize(width: 0, height: -3)

        let accent = RoobytesAccent.bright.withAlphaComponent(accentBorderAlpha)
        let rim = NSColor.white.withAlphaComponent(dark ? 0.18 : 0.28)
        glass.layer?.borderWidth = borderWidth
        glass.layer?.borderColor =
            accent.blended(withFraction: 0.45, of: rim)?.cgColor ?? accent.cgColor

        tint.wantsLayer = true
        tint.layer?.backgroundColor =
            NSColor.black.withAlphaComponent(dark ? tintAlpha : tintAlpha * 0.55).cgColor

        if let highlight {
            highlight.wantsLayer = true
            highlight.layer?.backgroundColor =
                NSColor.white.withAlphaComponent(highlightAlpha).cgColor
        }
    }
}

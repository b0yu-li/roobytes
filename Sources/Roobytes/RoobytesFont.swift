import AppKit

/// Shared editor typography — prefers PT Mono, falls back to Menlo / system mono.
enum RoobytesFont {
    static let bodySize: CGFloat = 14
    static let codeSize: CGFloat = 13

    static func regular(size: CGFloat = bodySize) -> NSFont {
        NSFont(name: "PTMono-Regular", size: size)
            ?? NSFont(name: "PT Mono", size: size)
            ?? NSFont(name: "Menlo-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func bold(size: CGFloat) -> NSFont {
        NSFont(name: "PTMono-Bold", size: size)
            ?? NSFont(name: "PT Mono Bold", size: size)
            ?? NSFont(name: "Menlo-Bold", size: size)
            ?? NSFontManager.shared.convert(regular(size: size), toHaveTrait: .boldFontMask)
    }

    static func italic(size: CGFloat = bodySize) -> NSFont {
        // PT Mono has no italic — synthesize from regular.
        NSFontManager.shared.convert(regular(size: size), toHaveTrait: .italicFontMask)
    }
}

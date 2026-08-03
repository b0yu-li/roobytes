import Foundation

/// Policy for `j` / `k` in a soft-wrapped editor.
public enum VimVerticalMotion {
    /// Bare `j` / `k` walk **display rows**, so the wrapped half of a long paragraph is
    /// reachable — the usual prose remap (`v:count ? 'j' : 'gj'`). A typed count keeps
    /// **logical lines**: the gutter draws one hybrid relative number per logical line,
    /// so `5j` has to land on the row labelled `5`.
    public static func usesDisplayRows(hasCount: Bool, gPrefixed: Bool) -> Bool {
        gPrefixed || !hasCount
    }
}

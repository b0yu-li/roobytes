import Foundation

/// Resolve an alphanumeric word under a UTF-16 caret (vim `K` / Look Up).
public enum WordUnderCaret {
    /// Column is UTF-16 (matches `MarkdownBridge.MarkdownCaret.column` / `NSString` offsets).
    public static func word(in line: String, column: Int) -> String? {
        guard let range = range(in: line as NSString, at: column) else { return nil }
        return (line as NSString).substring(with: range)
    }

    /// UTF-16 range of the word spanning `column`, if any.
    /// At EOF (`column == length`), uses the last character (vim block caret past end).
    public static func range(in ns: NSString, at column: Int) -> NSRange? {
        let len = ns.length
        guard len > 0 else { return nil }
        var i = max(0, min(column, len))
        if i >= len {
            i = len - 1
        }
        guard isWordUTF16(ns.character(at: i)) else { return nil }

        var start = i
        while start > 0, isWordUTF16(ns.character(at: start - 1)) {
            start -= 1
        }
        var end = i
        while end + 1 < len, isWordUTF16(ns.character(at: end + 1)) {
            end += 1
        }
        return NSRange(location: start, length: end - start + 1)
    }

    /// Same token class as buffer word completion (`letters` / digits / `_` / `-`).
    private static func isWordUTF16(_ unit: unichar) -> Bool {
        if unit == 0x5F || unit == 0x2D { return true } // _ -
        if unit >= 0x30, unit <= 0x39 { return true }
        if unit >= 0x41, unit <= 0x5A { return true }
        if unit >= 0x61, unit <= 0x7A { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.letters.contains(scalar)
    }
}

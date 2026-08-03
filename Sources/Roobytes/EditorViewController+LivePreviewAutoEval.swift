import AppKit

@MainActor
extension EditorViewController {
    /// After typing `=`, expand `12+3+4=` → `12+3+4=19` on the active Insert line.
    func tryAutoEvaluateSumAfterEquals() {
        guard vimMode == .insert else { return }
        guard !isApplyingDocument else { return }

        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location > 0 else { return }
        // Just typed `=` — caret sits immediately after it.
        guard ns.character(at: sel.location - 1) == 61 else { return } // '='

        var paraStart = 0, paraEnd = 0, contentsEnd = 0
        ns.getParagraphStart(
            &paraStart,
            end: &paraEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: sel.location - 1, length: 0)
        )
        let prefixLen = sel.location - paraStart
        guard prefixLen > 1 else { return }
        let prefix = ns.substring(with: NSRange(location: paraStart, length: prefixLen))

        guard let result = Self.evaluateTrailingSumExpression(prefix) else { return }
        insertAutoEvalResult(result, at: sel.location)
    }

    /// After typing `(`, expand `10:00 - 11:33 (` → `10:00 - 11:33 (93')`.
    func tryAutoEvaluateTimeRangeDuration() {
        guard vimMode == .insert else { return }
        guard !isApplyingDocument else { return }

        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location > 0 else { return }
        guard ns.character(at: sel.location - 1) == 40 else { return } // '('

        var paraStart = 0, paraEnd = 0, contentsEnd = 0
        ns.getParagraphStart(
            &paraStart,
            end: &paraEnd,
            contentsEnd: &contentsEnd,
            for: NSRange(location: sel.location - 1, length: 0)
        )
        let prefixLen = sel.location - paraStart
        guard prefixLen > 1 else { return }
        let prefix = ns.substring(with: NSRange(location: paraStart, length: prefixLen))

        guard let result = TimeRangeDuration.insertion(afterTypingOpenParenIn: prefix) else { return }
        insertAutoEvalResult(result, at: sel.location)
    }

    private func insertAutoEvalResult(_ insert: String, at location: Int) {
        isApplyingDocument = true
        textView.insertText(insert, replacementRange: NSRange(location: location, length: 0))
        isApplyingDocument = false

        if let active = activeSourceLine {
            syncLineAtIndex(active)
        }
        delegate?.editorDidChangeText(self)
        updateLineNumberGutter()
    }

    /// `…120+23+121+60=` → `"324"`; requires ≥2 operands joined by `+`.
    private static func evaluateTrailingSumExpression(_ prefixIncludingEquals: String) -> String? {
        guard prefixIncludingEquals.hasSuffix("=") else { return nil }
        let beforeEquals = String(prefixIncludingEquals.dropLast())
        // Match a sum at the end: digits (optional decimal) joined by +.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![0-9.])(\d+(?:\.\d+)?(?:\s*\+\s*\d+(?:\.\d+)?)+)\s*$"#
        ) else { return nil }
        let ns = beforeEquals as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: beforeEquals, options: [], range: full),
              match.numberOfRanges >= 2
        else { return nil }
        let expr = ns.substring(with: match.range(at: 1))
        let parts = expr.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2 else { return nil }

        var sum = Decimal(0)
        var allIntegers = true
        for part in parts {
            if part.contains(".") { allIntegers = false }
            guard let value = Decimal(string: part) else { return nil }
            sum += value
        }

        if allIntegers {
            let intSum = NSDecimalNumber(decimal: sum).intValue
            return String(intSum)
        }
        // Trim trailing zeros for decimals.
        let num = NSDecimalNumber(decimal: sum)
        return num.stringValue
    }
}

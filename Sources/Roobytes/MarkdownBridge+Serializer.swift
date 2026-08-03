import AppKit

// MARK: - Attributed → Markdown

extension MarkdownBridge {
    public static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }

        var lines: [String] = []
        let ns = attributed.string as NSString
        var location = 0
        var inCode = false

        while location < ns.length {
            var paraStart = 0
            var paraEnd = 0
            var contentsEnd = 0
            ns.getParagraphStart(
                &paraStart,
                end: &paraEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )

            let contentRange = NSRange(location: paraStart, length: max(0, contentsEnd - paraStart))
            let kind: MDBlock
            if contentRange.length > 0, paraStart < attributed.length {
                kind = blockKind(at: paraStart, in: attributed)
            } else {
                kind = .paragraph
            }

            let inlineAttr = contentRange.length > 0
                ? attributed.attributedSubstring(from: contentRange)
                : NSAttributedString()
            let plain = inlineAttr.string
            let inline = encodeInline(inlineAttr)
            let indent = indentPrefix(at: paraStart, in: attributed)

            if plain.hasPrefix("```") {
                lines.append(plain)
                inCode.toggle()
            } else if inCode || kind == .codeBlock {
                lines.append(indent + plain)
            } else {
                switch kind {
                case .h1, .h2, .h3, .h4:
                    if isRawHeadingLine(plain) {
                        lines.append(plain)
                    } else {
                        let hashes: String
                        switch kind {
                        case .h1: hashes = "#"
                        case .h2: hashes = "##"
                        case .h3: hashes = "###"
                        case .h4: hashes = "####"
                        default: hashes = "###"
                        }
                        lines.append("\(indent)\(hashes) \(inline)")
                    }
                case .bullet:
                    lines.append("\(indent)+ \(stripBulletPrefix(inline))")
                case .numbered:
                    lines.append("\(indent)1. \(stripNumberedPrefix(inline))")
                case .task:
                    if isRawTaskSlugLine(plain) {
                        lines.append(indent + plain)
                    } else {
                        let (state, text) = stripTaskPrefix(from: inlineAttr)
                        lines.append("\(indent)+ \(state.markdownBracket) \(text)")
                    }
                case .quote:
                    lines.append("\(indent)> \(inline)")
                case .thematicBreak:
                    lines.append("---")
                case .paragraph, .codeBlock:
                    lines.append(indent + inline)
                }
            }

            if paraEnd <= location { break }
            location = paraEnd
        }

        if inCode {
            lines.append("```")
        }

        var result = lines.joined(separator: "\n")
        let wantTrailing = trailingNewlineCount(ns)
        var haveTrailing = trailingNewlineCount(result as NSString)
        while haveTrailing < wantTrailing {
            result += "\n"
            haveTrailing += 1
        }
        return result
    }

    private static func trailingNewlineCount(_ ns: NSString) -> Int {
        var count = 0
        var i = ns.length - 1
        while i >= 0, ns.character(at: i) == 10 {
            count += 1
            i -= 1
        }
        return count
    }

    private static func blockKind(at location: Int, in attributed: NSAttributedString) -> MDBlock {
        guard location < attributed.length else { return .paragraph }
        let attrs = attributed.attributes(at: location, effectiveRange: nil)
        if let raw = attrs[.mdBlock] as? String, let kind = MDBlock(rawValue: raw) {
            return kind
        }
        if let font = attrs[.font] as? NSFont {
            let size = font.pointSize
            if size >= 24 { return .h1 }
            if size >= 19 { return .h2 }
            if size >= 16.5 { return .h3 }
        }
        return .paragraph
    }

    private static func indentPrefix(at location: Int, in attributed: NSAttributedString) -> String {
        guard location < attributed.length else { return "" }
        let level = attributed.attribute(.mdIndent, at: location, effectiveRange: nil) as? Int ?? 0
        guard level > 0 else { return "" }
        return String(repeating: "  ", count: level)
    }

    private static func encodeInline(_ attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        var output = ""
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { attrs, range, _ in
            var chunk = (attributed.string as NSString).substring(with: range)
            if chunk == "\n" {
                output += chunk
                return
            }
            let inlineRole = attrs[.mdInline] as? String
            let isCode = inlineRole == "code"
            let font = attrs[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let block = attrs[.mdBlock] as? String
            let isHeading = ["h1", "h2", "h3", "h4"].contains(block ?? "")
            let isBold = traits.contains(.boldFontMask) && !isHeading
            let isItalic = MarkdownBridge.isItalic(attrs)
            let strike = (attrs[.strikethroughStyle] as? Int).map { $0 != 0 } ?? false
            let isTask = block == MDBlock.task.rawValue
            if chunk == "\u{FFFC}" {
                return
            }

            if isCode {
                chunk = "`\(chunk)`"
            } else {
                if isBold && isItalic {
                    chunk = "***\(chunk)***"
                } else if isBold {
                    chunk = "**\(chunk)**"
                } else if isItalic {
                    chunk = "*\(chunk)*"
                }
                if strike && !isTask {
                    chunk = "~~\(chunk)~~"
                }
            }
            output += chunk
        }
        return output
    }

    private static func stripBulletPrefix(_ text: String) -> String {
        var t = text
        for prefix in ["•  ", "• ", "- ", "* ", "+ "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count))
            break
        }
        return sanitizeTaskOrBulletText(t).text
    }

    private static func stripNumberedPrefix(_ text: String) -> String {
        if let regex = try? NSRegularExpression(pattern: #"^\d+\.\s+"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text)
        {
            return String(text[range.upperBound...])
        }
        return text
    }

    private static func isRawTaskSlugLine(_ plain: String) -> Bool {
        matchTask(plain) != nil
    }

    private static func isRawHeadingLine(_ plain: String) -> Bool {
        let trimmed = plain.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("# ")
            || trimmed.hasPrefix("## ")
            || trimmed.hasPrefix("### ")
            || trimmed.hasPrefix("#### ")
    }

    private static func stripTaskPrefix(from attributed: NSAttributedString) -> (TaskMarkerState, String) {
        let plain = attributed.string
        if plain.hasPrefix("\u{FFFC}") {
            let state: TaskMarkerState
            if let raw = attributed.attribute(.mdTaskState, at: 0, effectiveRange: nil) as? String,
               let parsed = TaskMarkerState(rawValue: raw)
            {
                state = parsed
            } else {
                let checked = attributed.attribute(.mdTaskChecked, at: 0, effectiveRange: nil) as? Bool == true
                state = checked ? .done : .open
            }
            var loc = 1
            let ns = plain as NSString
            while loc < ns.length {
                let ch = ns.character(at: loc)
                if ch == 32 || ch == 9 { loc += 1 } else { break }
            }
            let remLen = attributed.length - loc
            guard remLen > 0 else { return (state, "") }
            let rem = attributed.attributedSubstring(from: NSRange(location: loc, length: remLen))
            return (state, encodeInline(rem))
        }
        return stripTaskPrefix(encodeInline(attributed))
    }

    private static func stripTaskPrefix(_ text: String) -> (TaskMarkerState, String) {
        if let task = matchTask(text.trimmingCharacters(in: .whitespaces)) {
            return (task.state, task.text)
        }
        let cleaned = sanitizeTaskOrBulletText(text)
        if let state = cleaned.state {
            return (state, cleaned.text)
        }
        if text.hasPrefix("[~] ") {
            return (.deprecated, String(text.dropFirst(4)))
        }
        if text.hasPrefix("[!] ") {
            return (.focused, String(text.dropFirst(4)))
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return (.done, String(text.dropFirst(4)))
        }
        if text.hasPrefix("[ ] ") { return (.open, String(text.dropFirst(4))) }
        return (.open, cleaned.text)
    }
}

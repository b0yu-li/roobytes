import AppKit
import Foundation

extension NSAttributedString.Key {
    static let mdBlock = NSAttributedString.Key("Roobytes.block")
    static let mdIndent = NSAttributedString.Key("Roobytes.indent")
    /// Explicit inline role: "code" | "bold" | "italic" | "link" | "tag" — never infer code from monospace fonts (PT Mono is mono).
    public static let mdInline = NSAttributedString.Key("Roobytes.inline")
    /// Legacy: `true` when task is done (`[x]`). Prefer `mdTaskState`.
    static let mdTaskChecked = NSAttributedString.Key("Roobytes.taskChecked")
    /// Task marker state raw value: `open` | `focused` | `done` | `deprecated`.
    static let mdTaskState = NSAttributedString.Key("Roobytes.taskState")
    /// Markdown source line index for this paragraph (stable when nested list folds hide lines).
    public static let mdSourceLine = NSAttributedString.Key("Roobytes.sourceLine")
    /// Visual-only fold cue suffix on a collapsed parent (` ▸N`).
    static let mdFoldCue = NSAttributedString.Key("Roobytes.foldCue")
}

/// Checkbox marker on a task line: `[ ]` / `[!]` (focus) / `[x]` / `[~]` (deprecated).
enum TaskMarkerState: String, Equatable, Hashable {
    case open
    case focused
    case done
    case deprecated

    var markdownBracket: String {
        switch self {
        case .open: return "[ ]"
        case .focused: return "[!]"
        case .done: return "[x]"
        case .deprecated: return "[~]"
        }
    }

    /// Collapsed Live Preview glyph (before attachment replace).
    var previewMark: Character {
        switch self {
        case .open: return "☐"
        case .focused: return "▣"
        case .done: return "☑"
        case .deprecated: return "☒"
        }
    }

    /// Still an actionable (not-done) task.
    var isOpenLike: Bool {
        switch self {
        case .open, .focused: return true
        case .done, .deprecated: return false
        }
    }
}

enum MDBlock: String {
    case paragraph
    case h1
    case h2
    case h3
    case h4
    case bullet
    case numbered
    case task
    case codeBlock
    case quote
    case thematicBreak
}

/// Line-oriented markdown ↔ attributed text.
/// Preserves source newlines (Foundation's markdown AST was collapsing diary notes into a wall of text).
public enum MarkdownBridge {
    private static let bodySize: CGFloat = RoobytesFont.bodySize
    private static let codeSize: CGFloat = RoobytesFont.codeSize
    /// Collapsed bullet prefix. Length must match raw `"+ "` (marker + one space).
    private static let bulletMarker = "• "
    static let bulletMarkerUTF16Length = (bulletMarker as NSString).length

    // MARK: - Markdown → Attributed

    private struct ParsedLine {
        var block: MDBlock
        var visibleText: String
        var indentLevel: Int = 0
        var taskState: TaskMarkerState? = nil
    }


    /// When `activeSourceLine` matches this line index, show raw markdown (Live Preview).
    /// `foldedParentLines` hides nested children in the view only (markdown source unchanged).
    /// When a `[!]` focus task exists, non-focus / non-active lines are strongly dimmed.
    public static func attributedString(
        from markdown: String,
        activeSourceLine: Int? = nil,
        foldedParentLines: Set<Int> = []
    ) -> NSAttributedString {
        guard !markdown.isEmpty else {
            return NSAttributedString(string: "", attributes: bodyAttributes(block: .paragraph))
        }

        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let focusLineIndex = focusTaskLineIndex(in: lines)
        let hidden = hiddenLineIndices(foldedParents: foldedParentLines, lines: lines)
        let result = NSMutableAttributedString()
        var inCodeFence = false
        var appendedAny = false
        var previousVisibleLine: Int?

        for (index, line) in lines.enumerated() {
            if line.hasPrefix("```") {
                inCodeFence.toggle()
            }

            if hidden.contains(index) { continue }

            if appendedAny {
                // Terminating newline belongs to the previous visible line (not the next).
                // Tagging it with the next index made empty paragraphs steal the following
                // line’s identity and broke caret maps (`A` / Insert restyle).
                var nl = bodyAttributes(block: .paragraph)
                if let prev = previousVisibleLine {
                    nl[.mdSourceLine] = prev
                    if shouldDimForFocus(
                        lineIndex: prev,
                        focusLineIndex: focusLineIndex,
                        activeSourceLine: activeSourceLine
                    ) {
                        nl[.foregroundColor] = RoobytesTheme.editorTertiary
                    }
                }
                result.append(NSAttributedString(string: "\n", attributes: nl))
            }
            appendedAny = true
            previousVisibleLine = index

            if line.hasPrefix("```") {
                var attrs = bodyAttributes(block: .codeBlock)
                attrs[.foregroundColor] = RoobytesTheme.editorTertiary
                attrs[.mdSourceLine] = index
                var piece = NSAttributedString(string: line, attributes: attrs) as NSAttributedString
                if shouldDimForFocus(lineIndex: index, focusLineIndex: focusLineIndex, activeSourceLine: activeSourceLine) {
                    piece = applyingFocusDim(piece)
                }
                result.append(piece)
                continue
            }

            if inCodeFence {
                var attrs = bodyAttributes(block: .codeBlock)
                attrs[.mdSourceLine] = index
                var piece = NSAttributedString(string: line, attributes: attrs) as NSAttributedString
                if shouldDimForFocus(lineIndex: index, focusLineIndex: focusLineIndex, activeSourceLine: activeSourceLine) {
                    piece = applyingFocusDim(piece)
                }
                result.append(piece)
                continue
            }

            let foldCueCount: Int? = foldedParentLines.contains(index)
                ? (childLineRange(parent: index, in: lines).map(\.count))
                : nil
            result.append(
                attributedLine(
                    line,
                    lineIndex: index,
                    activeSourceLine: activeSourceLine,
                    foldCueChildCount: foldCueCount,
                    focusLineIndex: focusLineIndex
                )
            )
        }

        return result
    }

    /// One markdown line → attributed fragment (no trailing newline). Used by incremental restyle.
    static func attributedLine(
        _ line: String,
        lineIndex: Int,
        activeSourceLine: Int?,
        foldCueChildCount: Int? = nil,
        focusLineIndex: Int? = nil
    ) -> NSAttributedString {
        let base: NSAttributedString
        if line.hasPrefix("```") {
            var attrs = bodyAttributes(block: .codeBlock)
            attrs[.foregroundColor] = RoobytesTheme.editorTertiary
            attrs[.mdSourceLine] = lineIndex
            base = NSAttributedString(string: line, attributes: attrs)
        } else {
            let parsed = parseLine(line, lineIndex: lineIndex, activeSourceLine: activeSourceLine)
            let fragment: NSAttributedString
            if lineIndex == activeSourceLine {
                let attr = activeSourceLineAttributed(parsed.visibleText, block: parsed.block)
                fragment = taskState(in: parsed.visibleText) == .focused
                    ? applyingFocusWash(attr)
                    : attr
            } else {
                fragment = inlineAttributed(
                    parsed.visibleText,
                    block: parsed.block,
                    indentLevel: parsed.indentLevel,
                    taskState: parsed.taskState
                )
            }
            base = taggingSourceLine(fragment, lineIndex: lineIndex)
        }

        let withCue: NSAttributedString
        if let count = foldCueChildCount, count > 0 {
            let cue = NSMutableAttributedString(attributedString: base)
            var cueAttrs = bodyAttributes(block: .paragraph)
            cueAttrs[.foregroundColor] = RoobytesTheme.editorTertiary
            cueAttrs[.mdSourceLine] = lineIndex
            cueAttrs[.mdFoldCue] = true
            cue.append(NSAttributedString(string: " ▸\(count)", attributes: cueAttrs))
            withCue = cue
        } else {
            withCue = base
        }

        guard shouldDimForFocus(
            lineIndex: lineIndex,
            focusLineIndex: focusLineIndex,
            activeSourceLine: activeSourceLine
        ) else {
            return withCue
        }
        return applyingFocusDim(withCue)
    }

    private static func shouldDimForFocus(
        lineIndex: Int,
        focusLineIndex: Int?,
        activeSourceLine: Int?
    ) -> Bool {
        guard let focusLineIndex else { return false }
        if lineIndex == focusLineIndex { return false }
        if lineIndex == activeSourceLine { return false }
        return true
    }

    /// Strong de-emphasis for non-focused lines while a `[!]` task exists.
    private static func applyingFocusDim(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let dim = RoobytesTheme.editorTertiary
        let full = NSRange(location: 0, length: result.length)
        result.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            // Leave checkbox / attachment glyphs at full strength.
            if attrs[.attachment] != nil { return }
            // Keep link / tag affordance visible under focus dim.
            if let role = attrs[.mdInline] as? String, role == "link" || role == "tag" { return }
            // Keep accent heading colors in Normal / Live Preview while focus is on.
            if let block = attrs[.mdBlock] as? String, ["h2", "h3", "h4"].contains(block) {
                return
            }
            result.addAttribute(.foregroundColor, value: dim, range: range)
        }
        return result
    }

    private static func taggingSourceLine(_ attributed: NSAttributedString, lineIndex: Int) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attributed)
        m.addAttribute(.mdSourceLine, value: lineIndex, range: NSRange(location: 0, length: m.length))
        return m
    }

    /// Strip visual fold cue (` ▸N`) before column mapping.
    static func stripFoldCue(_ visible: String) -> String {
        guard let range = visible.range(of: #" ▸\d+$"#, options: .regularExpression) else {
            return visible
        }
        return String(visible[..<range.lowerBound])
    }

    /// Active (raw markdown) line — must share the same line box as the rendered form.
    private static func activeSourceLineAttributed(_ text: String, block: MDBlock) -> NSAttributedString {
        // Use the real block’s paragraph metrics (esp. task/bullet fixed line height).
        // Previously we forced `.paragraph` here, which made Insert mode sit tight above / loose below.
        let styleBlock: MDBlock
        switch block {
        case .h1, .h2, .h3, .h4, .task, .bullet, .numbered, .quote, .codeBlock:
            styleBlock = block
        default:
            styleBlock = .paragraph
        }

        var attrs = bodyAttributes(block: styleBlock, indentLevel: 0)
        // Raw line already includes leading indent spaces — don’t add list headIndent again.
        if block == .task || block == .bullet || block == .numbered {
            let style = (paragraphStyle(for: block, indentLevel: 0) as NSParagraphStyle)
                .mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = 0
            style.firstLineHeadIndent = 0
            style.paragraphSpacing = 2
            style.paragraphSpacingBefore = 0
            let lineBox = fixedLineHeight(for: block)
            style.minimumLineHeight = lineBox
            style.lineSpacing = 0
            attrs[.paragraphStyle] = style
            attrs[.font] = font(for: .paragraph) // body size even for tasks — matches rendered body text
            attrs[.mdBlock] = block.rawValue
        }
        // Headings: keep spacing metrics, but body-size font so `### Title` reads as source
        // (not a second rendered heading stacked on the decorated one).
        if block == .h1 || block == .h2 || block == .h3 || block == .h4 {
            attrs[.font] = font(for: .paragraph)
            attrs[.mdBlock] = block.rawValue
        }

        let result = NSMutableAttributedString(string: text, attributes: attrs)
        let ns = text as NSString
        var start = 0
        while start < ns.length {
            let ch = ns.character(at: start)
            if ch == 32 || ch == 9 { start += 1 } else { break }
        }
        let rest = ns.substring(from: start)
        let markers = [
            "#### ", "### ", "## ", "# ", "> ",
            "+ [ ] ", "+ [!] ", "+ [x] ", "+ [X] ", "+ [~] ",
            "- [ ] ", "- [!] ", "- [x] ", "- [X] ", "- [~] ",
            "* [ ] ", "* [!] ", "* [x] ", "* [X] ", "* [~] ",
            "+ ", "- ", "* ",
        ]
        for marker in markers where rest.hasPrefix(marker) {
            let len = start + (marker as NSString).length
            result.addAttribute(
                .foregroundColor,
                value: RoobytesTheme.editorSecondary,
                range: NSRange(location: 0, length: min(len, ns.length))
            )
            break
        }
        applyHTTPLinkHighlights(to: result)
        applyTagHighlights(to: result)
        return result
    }

    /// Accent + underline for bare `http(s)` URLs and markdown link labels/URLs.
    /// Does not set `.link` (avoids AppKit click interception; open via `gx` / `gX`).
    private static func applyHTTPLinkHighlights(to result: NSMutableAttributedString) {
        guard result.length > 0 else { return }
        let text = result.string
        for range in URLUnderCaret.httpURLRanges(in: text) {
            guard range.location != NSNotFound, NSMaxRange(range) <= result.length else { continue }
            applyLinkVisuals(to: result, range: range)
        }
        for pair in URLUnderCaret.markdownLinkHighlightRanges(in: text) {
            if pair.label.length > 0, NSMaxRange(pair.label) <= result.length {
                applyLinkVisuals(to: result, range: pair.label)
            }
            if pair.url.length > 0, NSMaxRange(pair.url) <= result.length {
                applyLinkVisuals(to: result, range: pair.url)
            }
        }
    }

    private static func applyTagHighlights(to result: NSMutableAttributedString) {
        guard result.length > 0 else { return }
        for range in TagHighlight.ranges(in: result.string) {
            guard range.length > 0, NSMaxRange(range) <= result.length else { continue }
            applyTagVisuals(to: result, range: range)
        }
    }

    private static func applyLinkVisuals(to result: NSMutableAttributedString, range: NSRange) {
        // Skip code chips — backticks win.
        var skip = false
        result.enumerateAttribute(.mdInline, in: range, options: []) { value, _, stop in
            if value as? String == "code" {
                skip = true
                stop.pointee = true
            }
        }
        guard !skip else { return }
        result.addAttributes(
            [
                .foregroundColor: RoobytesAccent.linkForeground,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: RoobytesAccent.linkForeground,
                .mdInline: "link",
            ],
            range: range
        )
    }

    private static func applyTagVisuals(to result: NSMutableAttributedString, range: NSRange) {
        var skip = false
        result.enumerateAttribute(.mdInline, in: range, options: []) { value, _, stop in
            if let role = value as? String, role == "code" || role == "link" {
                skip = true
                stop.pointee = true
            }
        }
        guard !skip else { return }
        result.addAttributes(
            [
                .foregroundColor: RoobytesAccent.tagForeground,
                .mdInline: "tag",
            ],
            range: range
        )
    }

    private static func parseLine(
        _ line: String,
        lineIndex: Int = 0,
        activeSourceLine: Int? = nil
    ) -> ParsedLine {
        let (indent, rest) = splitIndent(line)
        let level = indentLevel(from: indent)

        // Live Preview: caret line is always raw source.
        if lineIndex == activeSourceLine {
            let block = classifyBlock(rest)
            return ParsedLine(block: block, visibleText: line, indentLevel: 0)
        }

        if rest == "---" || rest == "***" || rest == "___" {
            return ParsedLine(block: .thematicBreak, visibleText: "────────", indentLevel: level)
        }
        if rest.hasPrefix("#### ") {
            return ParsedLine(block: .h4, visibleText: sanitizeHeadingText(String(rest.dropFirst(5))), indentLevel: level)
        }
        if rest.hasPrefix("### ") {
            return ParsedLine(block: .h3, visibleText: sanitizeHeadingText(String(rest.dropFirst(4))), indentLevel: level)
        }
        if rest.hasPrefix("## ") {
            return ParsedLine(block: .h2, visibleText: sanitizeHeadingText(String(rest.dropFirst(3))), indentLevel: level)
        }
        if rest.hasPrefix("# ") {
            return ParsedLine(block: .h1, visibleText: sanitizeHeadingText(String(rest.dropFirst(2))), indentLevel: level)
        }
        if rest.hasPrefix("> ") {
            return ParsedLine(block: .quote, visibleText: String(rest.dropFirst(2)), indentLevel: level)
        }
        if rest.hasPrefix(">") {
            return ParsedLine(block: .quote, visibleText: String(rest.dropFirst(1)), indentLevel: level)
        }

        if let task = matchTask(rest) {
            let cleaned = sanitizeTaskOrBulletText(task.text)
            let state = cleaned.state ?? task.state
            return ParsedLine(
                block: .task,
                visibleText: String(state.previewMark) + cleaned.text,
                indentLevel: level,
                taskState: state
            )
        }

        if let bullet = matchBullet(rest) {
            let cleaned = sanitizeTaskOrBulletText(bullet).text
            // Two UTF-16 units — same as raw `"+ "` / `"- "` / `"* "` so the body doesn’t jump on edit.
            return ParsedLine(
                block: .bullet,
                visibleText: bulletMarker + cleaned,
                indentLevel: level
            )
        }

        if let numbered = matchNumbered(rest) {
            return ParsedLine(
                block: .numbered,
                visibleText: "\(numbered.ordinal).  " + numbered.text,
                indentLevel: level
            )
        }

        return ParsedLine(block: .paragraph, visibleText: rest, indentLevel: level)
    }

    private static func classifyBlock(_ rest: String) -> MDBlock {
        if rest == "---" || rest == "***" || rest == "___" { return .thematicBreak }
        if rest.hasPrefix("#### ") { return .h4 }
        if rest.hasPrefix("### ") { return .h3 }
        if rest.hasPrefix("## ") { return .h2 }
        if rest.hasPrefix("# ") { return .h1 }
        if rest.hasPrefix(">") { return .quote }
        if matchTask(rest) != nil { return .task }
        if matchBullet(rest) != nil { return .bullet }
        if matchNumbered(rest) != nil { return .numbered }
        return .paragraph
    }

    static func splitIndent(_ line: String) -> (indent: String, rest: String) {
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == " " || ch == "\t" {
                i = line.index(after: i)
            } else {
                break
            }
        }
        return (String(line[..<i]), String(line[i...]))
    }

    static func indentLevel(from indent: String) -> Int {
        var spaces = 0
        for ch in indent {
            spaces += (ch == "\t") ? 4 : 1
        }
        return spaces / 2  // 2 spaces per visual level (common for nested lists)
    }

    /// UTF-16 column of the first body character (after indent + task/bullet/numbered marker).
    /// Used by vim `I` so Insert lands on content, not on `+` / `-` / `1.`.
    public static func contentStartColumn(in line: String) -> Int {
        let (indent, rest) = splitIndent(line)
        let indentLen = (indent as NSString).length
        guard !rest.isEmpty else { return indentLen }
        let restLen = (rest as NSString).length

        if let (_, text) = matchTask(rest) {
            return indentLen + restLen - (text as NSString).length
        }
        if let text = matchBullet(rest) {
            return indentLen + restLen - (text as NSString).length
        }
        if let numbered = matchNumbered(rest) {
            return indentLen + restLen - (numbered.text as NSString).length
        }
        return indentLen
    }

    /// Body text for Roobytes-flavored `yy`: drop list/task markers, then one leading `tag: ` (1–8 letters).
    /// Leaves `https://…` alone (no space after `:`).
    public static func yankableContent(of line: String) -> String {
        let start = contentStartColumn(in: line)
        let ns = line as NSString
        guard start >= 0, start <= ns.length else { return "" }
        var body = ns.substring(from: start)
        if let range = body.range(of: #"^[A-Za-z]{1,8}:\s+"#, options: .regularExpression) {
            body.removeSubrange(range)
        }
        return body
    }

    /// Indent + marker to continue after Enter on a task/bullet/numbered line.
    public static func listContinuationPrefix(for line: String) -> String {
        let (indent, rest) = splitIndent(line)
        if rest.hasPrefix("+ [") || rest.hasPrefix("- [") || rest.hasPrefix("* [") {
            let marker = rest.prefix(1) // +, -, or *
            return "\(indent)\(marker) [ ] "
        }
        if rest.hasPrefix("+ ") || rest.hasPrefix("- ") || rest.hasPrefix("* ") {
            let marker = rest.prefix(1)
            return "\(indent)\(marker) "
        }
        if rest.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            return indent + "1. "
        }
        return indent
    }

    /// UTF-16 length of leading indent + `#`/`##`/… marker, if this is a heading line.
    public static func headingMarkerLength(_ line: String) -> Int? {
        let (indent, rest) = splitIndent(line)
        for marker in ["#### ", "### ", "## ", "# "] where rest.hasPrefix(marker) {
            return (indent as NSString).length + (marker as NSString).length
        }
        return nil
    }

    /// Body text of `### Title` / `## Title` / etc., or nil if not a heading.
    public static func headingBody(_ line: String) -> String? {
        let (_, rest) = splitIndent(line)
        for marker in ["#### ", "### ", "## ", "# "] where rest.hasPrefix(marker) {
            return String(rest.dropFirst(marker.count))
        }
        return nil
    }

    static func matchTask(_ line: String) -> (state: TaskMarkerState, text: String)? {
        // Longer / more specific prefixes first (`[~]` / `[!]` before bare patterns).
        let patterns: [(String, TaskMarkerState)] = [
            ("- [~] ", .deprecated), ("* [~] ", .deprecated), ("+ [~] ", .deprecated),
            ("- [!] ", .focused), ("* [!] ", .focused), ("+ [!] ", .focused),
            ("- [x] ", .done), ("- [X] ", .done), ("- [ ] ", .open),
            ("* [x] ", .done), ("* [X] ", .done), ("* [ ] ", .open),
            ("+ [x] ", .done), ("+ [X] ", .done), ("+ [ ] ", .open),
            ("- [~]", .deprecated), ("* [~]", .deprecated), ("+ [~]", .deprecated),
            ("- [!]", .focused), ("* [!]", .focused), ("+ [!]", .focused),
            ("- [x]", .done), ("- [X]", .done), ("- [ ]", .open),
            ("* [x]", .done), ("* [X]", .done), ("* [ ]", .open),
            ("+ [x]", .done), ("+ [X]", .done), ("+ [ ]", .open),
            ("[~] ", .deprecated), ("[!] ", .focused), ("[x] ", .done), ("[X] ", .done), ("[ ] ", .open),
            ("[~]", .deprecated), ("[!]", .focused), ("[x]", .done), ("[X]", .done), ("[ ]", .open),
        ]
        for (prefix, state) in patterns where line.hasPrefix(prefix) {
            var text = String(line.dropFirst(prefix.count))
            if text.hasPrefix(" ") { text = String(text.dropFirst()) }
            return (state, text)
        }
        return nil
    }

    static func matchBullet(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ ", "-", "*", "+"] {
            if line.hasPrefix(prefix) {
                // Avoid treating "---" thematic (already handled) or negative ambiguity
                if prefix.count == 1, line.count > 1, line[line.index(after: line.startIndex)] != " " {
                    continue
                }
                var text = String(line.dropFirst(prefix.count))
                if text.hasPrefix(" ") { text = String(text.dropFirst()) }
                return text
            }
        }
        return nil
    }

    static func matchNumbered(_ line: String) -> (ordinal: Int, text: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges == 3,
              let ordRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line),
              let ordinal = Int(line[ordRange])
        else { return nil }
        return (ordinal, String(line[textRange]))
    }

    /// Strip corruption from live-restyle bugs (stacked ☐/☑/☒, wrapping backticks).
    static func sanitizeTaskOrBulletText(_ raw: String) -> (text: String, state: TaskMarkerState?) {
        var text = raw
        var state: TaskMarkerState?
        var guardCount = 0
        while guardCount < 20 {
            guardCount += 1
            text = text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("\u{FFFC}") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("☑") {
                state = .done
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("▣") {
                state = .focused
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("☒") {
                state = .deprecated
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("☐") || text.hasPrefix("□") {
                if state == nil { state = .open }
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("[~]") {
                state = .deprecated
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("[!]") {
                state = .focused
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("[x]") || text.hasPrefix("[X]") {
                state = .done
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("[ ]") {
                if state == nil { state = .open }
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if text.hasPrefix("•") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            // Only strip a *wrapping* backtick pair from old corruption — keep intentional `code`.
            if text.hasPrefix("`"), text.hasSuffix("`"), text.count >= 2,
               text.dropFirst().dropLast().contains("`") == false
            {
                text = String(text.dropFirst().dropLast())
                continue
            }
            break
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return (text, state)
    }

    private static func sanitizeHeadingText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("**"), text.hasSuffix("**"), text.count >= 4 {
            text = String(text.dropFirst(2).dropLast(2))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Alphanumeric / underscore before `i` — used so `_italic_` does not fire inside `snake_case`.
    private static func isWordChar(before i: String.Index, in text: String) -> Bool {
        guard i > text.startIndex else { return false }
        let prev = text[text.index(before: i)]
        return prev.isLetter || prev.isNumber || prev == "_"
    }

    private static func isWordChar(after i: String.Index, in text: String) -> Bool {
        let next = text.index(after: i)
        guard next < text.endIndex else { return false }
        let ch = text[next]
        return ch.isLetter || ch.isNumber || ch == "_"
    }

    /// First `_` after `open` that is not `__` and not followed by a word char.
    private static func closingUnderscore(after open: String.Index, in text: String) -> String.Index? {
        var j = text.index(after: open)
        while j < text.endIndex {
            if text[j] == "\n" { return nil }
            if text[j] == "_" {
                if text[j...].hasPrefix("__") {
                    // Skip `__` pair — not a single-underscore close.
                    j = text.index(j, offsetBy: 2)
                    continue
                }
                if !isWordChar(after: j, in: text) {
                    return j
                }
            }
            j = text.index(after: j)
        }
        return nil
    }

    /// Apply inline `**bold**`, `*italic*` / `_italic_`, `` `code` ``, `~~strike~~` within a line.
    private static func inlineAttributed(
        _ text: String,
        block: MDBlock,
        indentLevel: Int = 0,
        taskState: TaskMarkerState? = nil
    ) -> NSAttributedString {
        let base = bodyAttributes(block: block, indentLevel: indentLevel)
        guard !text.isEmpty else {
            return NSAttributedString(string: "", attributes: base)
        }

        let result = NSMutableAttributedString()
        var i = text.startIndex
        /// Done / deprecated tasks dim + strike remaining text (visual only).
        var muteTaskBody = false

        while i < text.endIndex {
            // Collapsed task checkbox → square attachment
            if block == .task, text[i] == "☐" || text[i] == "☑" || text[i] == "☒" || text[i] == "▣" {
                let state: TaskMarkerState
                switch text[i] {
                case "☑": state = .done
                case "☒": state = .deprecated
                case "▣": state = .focused
                default: state = .open
                }
                muteTaskBody = (state == .done || state == .deprecated)
                result.append(taskCheckboxAttachment(state: state, base: base))
                i = text.index(after: i)
                // Skip legacy spacing after the unicode marker — gap is visual only.
                while i < text.endIndex, text[i] == " " {
                    i = text.index(after: i)
                }
                continue
            }
            // Style raw slug marker in editable task lines
            if block == .task, i == text.startIndex,
               text.hasPrefix("+ [") || text.hasPrefix("- [") || text.hasPrefix("* [")
            {
                if let bracket = text.firstIndex(of: "]") {
                    let slugEnd = text.index(after: bracket)
                    let slug = String(text[..<slugEnd])
                    var slugAttrs = base
                    slugAttrs[.foregroundColor] = RoobytesTheme.editorSecondary
                    result.append(NSAttributedString(string: slug, attributes: slugAttrs))
                    i = slugEnd
                    if i < text.endIndex, text[i] == " " {
                        result.append(NSAttributedString(string: " ", attributes: base))
                        i = text.index(after: i)
                    }
                    continue
                }
            }

            if text[i...].hasPrefix("**"),
               let closeRange = text.range(of: "**", range: text.index(i, offsetBy: 2)..<text.endIndex)
            {
                let contentStart = text.index(i, offsetBy: 2)
                let content = String(text[contentStart..<closeRange.lowerBound])
                var attrs = base
                if let font = attrs[.font] as? NSFont {
                    attrs[.font] = derivedFont(font, trait: .boldFontMask)
                }
                applyCompletedTaskStyle(&attrs, enabled: muteTaskBody)
                result.append(NSAttributedString(string: content, attributes: attrs))
                i = closeRange.upperBound
                continue
            }

            if text[i...].hasPrefix("~~"),
               let closeRange = text.range(of: "~~", range: text.index(i, offsetBy: 2)..<text.endIndex)
            {
                let contentStart = text.index(i, offsetBy: 2)
                let content = String(text[contentStart..<closeRange.lowerBound])
                var attrs = base
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.strikethroughColor] = RoobytesTheme.editorForeground
                attrs[.underlineStyle] = 0
                applyCompletedTaskStyle(&attrs, enabled: muteTaskBody)
                result.append(NSAttributedString(string: content, attributes: attrs))
                i = closeRange.upperBound
                continue
            }

            // Inline code: only match short, single-line spans (avoid eating diary tokens)
            if text[i] == "`",
               let close = text[text.index(after: i)..<text.endIndex].firstIndex(of: "`")
            {
                let contentStart = text.index(after: i)
                let content = String(text[contentStart..<close])
                if !content.isEmpty, !content.contains("\n"), content.count <= 120 {
                    var attrs = base
                    attrs[.font] = RoobytesFont.regular(size: codeSize)
                    attrs[.foregroundColor] = RoobytesAccent.codeForeground
                    // Background drawn as rounded chips by RoobytesLayoutManager — avoid square NS fill.
                    attrs[.mdInline] = "code"
                    applyCompletedTaskStyle(&attrs, enabled: muteTaskBody)
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = text.index(after: close)
                    continue
                }
            }

            // Single *italic* (not **)
            if text[i] == "*",
               !text[i...].hasPrefix("**"),
               let close = text[text.index(after: i)..<text.endIndex].firstIndex(of: "*")
            {
                let contentStart = text.index(after: i)
                let content = String(text[contentStart..<close])
                if !content.isEmpty, !content.contains("\n"), !content.contains("*") {
                    var attrs = base
                    applyItalicStyle(to: &attrs)
                    applyCompletedTaskStyle(&attrs, enabled: muteTaskBody)
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = text.index(after: close)
                    continue
                }
            }

            // Single _italic_ (not __); skip word-interior `_` so snake_case stays literal.
            if text[i] == "_",
               !text[i...].hasPrefix("__"),
               !Self.isWordChar(before: i, in: text),
               let close = Self.closingUnderscore(after: i, in: text)
            {
                let contentStart = text.index(after: i)
                let content = String(text[contentStart..<close])
                if !content.isEmpty, !content.contains("\n"), !content.contains("_") {
                    var attrs = base
                    applyItalicStyle(to: &attrs)
                    applyCompletedTaskStyle(&attrs, enabled: muteTaskBody)
                    result.append(NSAttributedString(string: content, attributes: attrs))
                    i = text.index(after: close)
                    continue
                }
            }

            let next = text.index(after: i)
            var attrs = base
            applyCompletedTaskStyle(&attrs, enabled: muteTaskBody)
            result.append(NSAttributedString(string: String(text[i..<next]), attributes: attrs))
            i = next
        }

        if block == .bullet {
            alignBulletMarkerWidth(in: result, baseFont: base[.font] as? NSFont)
        }

        applyHTTPLinkHighlights(to: result)
        applyTagHighlights(to: result)

        if taskState == .focused {
            return applyingFocusWash(result)
        }
        return result
    }

    private static func applyingFocusWash(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > 0 else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let wash = RoobytesAccent.focusWash
        result.addAttribute(
            .backgroundColor,
            value: wash,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    /// Kern the `•` glyph so its advance matches `+` in the body mono font — kills edit jump.
    private static func alignBulletMarkerWidth(in result: NSMutableAttributedString, baseFont: NSFont?) {
        guard result.length > 0 else { return }
        let font = baseFont ?? RoobytesFont.regular()
        let ns = result.string as NSString
        guard ns.hasPrefix("•") else { return }
        let plusW = ("+" as NSString).size(withAttributes: [.font: font]).width
        let bulletW = ("•" as NSString).size(withAttributes: [.font: font]).width
        result.addAttribute(.kern, value: plusW - bulletW, range: NSRange(location: 0, length: 1))
        let markerLen = min(bulletMarkerUTF16Length, result.length)
        result.addAttribute(.foregroundColor, value: RoobytesTheme.editorSecondary, range: NSRange(location: 0, length: markerLen))
    }

    /// Accent fill + white tick (matches RoobytesAccent).
    /// HARD RULE: the glyph canvas must be exactly square (see `.cursor/rules/todo-checkbox.mdc`).
    private static var taskDoneFill: NSColor { RoobytesAccent.color }
    /// Visual size of the checkbox square (points). Keep ≥ bodySize so it reads clearly.
    private static let checkboxPointSize: CGFloat = 15
    /// Locked line box for tasks (checkbox + slug). Tight enough that the caret isn’t a tower.
    private static let taskLineHeight: CGFloat = {
        let font = RoobytesFont.regular(size: bodySize)
        let text = ceil(font.ascender - font.descender + max(0, font.leading))
        return max(text + 2, checkboxPointSize + 3)
    }()
    /// Bullets / numbered — match body glyph box so the caret fits the characters.
    private static let listLineHeight: CGFloat = {
        let font = RoobytesFont.regular(size: bodySize)
        return ceil(font.ascender - font.descender + max(0, font.leading)) + 2
    }()

    private static func fixedLineHeight(for block: MDBlock) -> CGFloat {
        block == .task ? taskLineHeight : listLineHeight
    }
    /// Transparent trailing pad after the square (not part of the icon — never stretch the square into this).
    private static let checkboxTrailingGap: CGFloat = 6

    private static func applyCompletedTaskStyle(
        _ attrs: inout [NSAttributedString.Key: Any],
        enabled: Bool
    ) {
        guard enabled else { return }
        attrs[.foregroundColor] = RoobytesTheme.editorSecondary
        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        attrs[.strikethroughColor] = RoobytesTheme.editorForeground
        attrs[.underlineStyle] = 0
    }

    private static func taskCheckboxAttachment(
        state: TaskMarkerState,
        base: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let font = RoobytesFont.regular(size: bodySize)
        let side = checkboxPointSize
        let gap = checkboxTrailingGap

        let cellImage = cachedCheckboxCellImage(state: state, side: side, gap: gap)

        let attachment = NSTextAttachment()
        attachment.image = cellImage
        // Center the square in the font em-box; attachment height == side (square), width includes gap only.
        let em = font.ascender - font.descender
        let y = font.descender + (em - side) / 2
        attachment.bounds = CGRect(x: 0, y: y, width: side + gap, height: side)

        let run = NSMutableAttributedString(attachment: attachment)
        var attrs = base
        attrs[.font] = font
        attrs[.mdTaskState] = state.rawValue
        attrs[.mdTaskChecked] = (state == .done)
        run.addAttributes(attrs, range: NSRange(location: 0, length: run.length))
        return run
    }

    private struct CheckboxCacheKey: Hashable {
        let state: TaskMarkerState
        let side: Int
        let gap: Int
        let appearance: String
        let accent: String
    }

    private final class CheckboxImageStore: @unchecked Sendable {
        var images: [CheckboxCacheKey: NSImage] = [:]
    }

    private static let checkboxImageStore = CheckboxImageStore()

    private static func cachedCheckboxCellImage(
        state: TaskMarkerState,
        side: CGFloat,
        gap: CGFloat
    ) -> NSImage {
        let appearance = UserDefaults.standard.string(forKey: RoobytesDefaultsKey.appearance) ?? "system"
        let accent = RoobytesAccent.preference.rawValue
        let key = CheckboxCacheKey(
            state: state,
            side: Int(side * 2),
            gap: Int(gap * 2),
            appearance: appearance,
            accent: accent
        )
        if let hit = checkboxImageStore.images[key] { return hit }

        let icon = makeSquareCheckboxImage(state: state, side: side)
        let cellSize = NSSize(width: side + gap, height: side)
        let cellImage = NSImage(size: cellSize, flipped: false) { _ in
            icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        checkboxImageStore.images[key] = cellImage
        return cellImage
    }

    /// Drop cached checkbox bitmaps when the accent preset changes.
    static func invalidateCheckboxImageCache() {
        checkboxImageStore.images.removeAll(keepingCapacity: true)
    }

    /// Perfectly square checkbox: open outline, focus accent fill, done accent+tick, deprecated muted+tilde.
    private static func makeSquareCheckboxImage(state: TaskMarkerState, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset: CGFloat = 1
            let box = rect.insetBy(dx: inset, dy: inset)
            let radius = max(2, side * 0.18)
            let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

            switch state {
            case .done:
                taskDoneFill.setFill()
                path.fill()

                let check = NSBezierPath()
                let x0 = box.minX + box.width * 0.22
                let y0 = box.minY + box.height * 0.48
                let x1 = box.minX + box.width * 0.42
                let y1 = box.minY + box.height * 0.28
                let x2 = box.minX + box.width * 0.78
                let y2 = box.minY + box.height * 0.68
                check.move(to: NSPoint(x: x0, y: y0))
                check.line(to: NSPoint(x: x1, y: y1))
                check.line(to: NSPoint(x: x2, y: y2))
                check.lineWidth = max(1.75, side * 0.12)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()

            case .focused:
                RoobytesAccent.color.setFill()
                path.fill()
                let bang = "!" as NSString
                let font = NSFont.systemFont(ofSize: max(9, side * 0.72), weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white,
                ]
                let size = bang.size(withAttributes: attrs)
                bang.draw(
                    at: NSPoint(
                        x: box.midX - size.width / 2,
                        y: box.midY - size.height / 2 - side * 0.02
                    ),
                    withAttributes: attrs
                )

            case .deprecated:
                NSColor.tertiaryLabelColor.setFill()
                path.fill()
                let tilde = "~" as NSString
                let font = NSFont.systemFont(ofSize: max(9, side * 0.78), weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.white,
                ]
                let size = tilde.size(withAttributes: attrs)
                tilde.draw(
                    at: NSPoint(
                        x: box.midX - size.width / 2,
                        y: box.midY - size.height / 2 - side * 0.04
                    ),
                    withAttributes: attrs
                )

            case .open:
                NSColor.secondaryLabelColor.setStroke()
                path.lineWidth = max(1.5, side * 0.1)
                path.stroke()
            }
            return true
        }
    }

    // MARK: - Visual attributes

    static func bodyAttributes(block: MDBlock, indentLevel: Int = 0) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: block),
            .foregroundColor: RoobytesTheme.editorForeground,
            .mdBlock: block.rawValue,
            .mdIndent: indentLevel,
            .paragraphStyle: paragraphStyle(for: block, indentLevel: indentLevel),
        ]
        switch block {
        case .codeBlock:
            attrs[.backgroundColor] = NSColor.controlBackgroundColor
            attrs[.foregroundColor] = RoobytesTheme.editorForeground
        case .quote:
            attrs[.foregroundColor] = RoobytesTheme.editorSecondary
        case .thematicBreak:
            attrs[.foregroundColor] = RoobytesTheme.editorTertiary
        case .task:
            attrs[.foregroundColor] = RoobytesTheme.editorForeground
        case .h2:
            attrs[.foregroundColor] = RoobytesAccent.heading2Foreground
        case .h3:
            attrs[.foregroundColor] = RoobytesAccent.heading3Foreground
        case .h4:
            attrs[.foregroundColor] = RoobytesAccent.heading4Foreground
        case .h1, .paragraph, .bullet, .numbered:
            break
        }
        // Muted checkbox glyph in collapsed task lines
        if block == .task, attrs[.foregroundColor] as? NSColor == RoobytesTheme.editorForeground {
            // applied per-run in inlineAttributed for ☐/☑ only — keep default here
        }
        return attrs
    }

    private static func font(for block: MDBlock) -> NSFont {
        switch block {
        case .h1: return RoobytesFont.bold(size: 26)
        case .h2: return RoobytesFont.bold(size: 20)
        case .h3: return RoobytesFont.bold(size: 17)
        case .h4: return RoobytesFont.bold(size: 15)
        case .codeBlock: return RoobytesFont.regular(size: codeSize)
        case .paragraph, .bullet, .numbered, .task, .quote, .thematicBreak:
            return RoobytesFont.regular(size: bodySize)
        }
    }

    /// Cache bold/italic derivations — `NSFontManager.convert` is relatively expensive per span.
    private static let derivedFontStore = DerivedFontStore()

    private final class DerivedFontStore: @unchecked Sendable {
        var fonts: [DerivedFontKey: NSFont] = [:]
    }

    private struct DerivedFontKey: Hashable {
        let name: String
        let size: Int
        let trait: UInt
    }

    private static func derivedFont(_ font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let key = DerivedFontKey(
            name: font.fontName,
            size: Int(font.pointSize * 100),
            trait: trait.rawValue
        )
        if let hit = derivedFontStore.fonts[key] { return hit }
        let next = NSFontManager.shared.convert(font, toHaveTrait: trait)
        derivedFontStore.fonts[key] = next
        return next
    }

    /// Slant applied when the body font has no true italic (PT Mono). Attribute-based so
    /// glyph advances stay monospace — a transformed `NSFont` would resize the run
    /// (`NSFont(descriptor:textTransform:)` yields a 1pt font) and break caret columns.
    static let syntheticObliqueness: CGFloat = 0.2

    /// Italicize `attrs` in place, falling back to a skew when the font lacks an italic face.
    private static func applyItalicStyle(to attrs: inout [NSAttributedString.Key: Any]) {
        attrs[.mdInline] = "italic"
        guard let font = attrs[.font] as? NSFont else { return }
        let italic = derivedFont(font, trait: .italicFontMask)
        attrs[.font] = italic
        if !NSFontManager.shared.traits(of: italic).contains(.italicFontMask) {
            attrs[.obliqueness] = syntheticObliqueness
        }
    }

    private static func paragraphStyle(for block: MDBlock, indentLevel: Int = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        let nest = CGFloat(indentLevel) * 16
        switch block {
        case .h1:
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 6
        case .h2:
            style.paragraphSpacingBefore = 12
            style.paragraphSpacing = 4
        case .h3, .h4:
            style.paragraphSpacingBefore = 8
            style.paragraphSpacing = 3
        case .bullet, .numbered, .task:
            style.headIndent = 18 + nest
            style.firstLineHeadIndent = nest
            style.paragraphSpacing = 2
            // Keep a stable first-line box for checkbox alignment, but do NOT cap
            // maximumLineHeight — wrapping tasks (long URLs / prose) were clipped and
            // could visually “swallow” into the line above.
            let lineBox = fixedLineHeight(for: block)
            style.minimumLineHeight = lineBox
            style.lineSpacing = 0
            style.lineHeightMultiple = 1
            style.paragraphSpacingBefore = 0
        case .codeBlock:
            style.paragraphSpacing = 2
            style.lineSpacing = 1
            style.headIndent = nest
            style.firstLineHeadIndent = nest
        case .quote:
            style.headIndent = 14 + nest
            style.firstLineHeadIndent = 14 + nest
            style.paragraphSpacing = 4
        case .paragraph:
            style.paragraphSpacing = 4
            style.headIndent = nest
            style.firstLineHeadIndent = nest
        case .thematicBreak:
            style.paragraphSpacing = 8
            style.alignment = .center
        }
        return style
    }

    // MARK: - Format helpers

    @MainActor
    static func applyBlock(_ block: MDBlock, to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = selectedParagraphRange(in: textView)
        storage.beginEditing()
        storage.addAttributes(bodyAttributes(block: block), range: range)
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let current = value as? NSFont else { return }
            let traits = NSFontManager.shared.traits(of: current)
            var base = font(for: block)
            if traits.contains(.boldFontMask) || traits.contains(.italicFontMask) {
                base = NSFontManager.shared.convert(base, toHaveTrait: traits)
            }
            storage.addAttribute(.font, value: base, range: subrange)
        }
        storage.endEditing()
        textView.typingAttributes = bodyAttributes(block: block)
        textView.didChangeText()
    }

    @MainActor
    static func toggleTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var typing = textView.typingAttributes
            toggle(trait, in: &typing)
            textView.typingAttributes = typing
            return
        }

        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range) { attrs, subrange, _ in
            var next = attrs
            toggle(trait, in: &next)
            updates.append((subrange, next))
        }
        storage.beginEditing()
        for (subrange, attrs) in updates {
            storage.setAttributes(attrs, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    /// Toggle a font trait; italic falls back to `.obliqueness` when the family has no italic face.
    private static func toggle(_ trait: NSFontTraitMask, in attrs: inout [NSAttributedString.Key: Any]) {
        let font = (attrs[.font] as? NSFont) ?? RoobytesFont.regular()
        guard trait == .italicFontMask else {
            let has = NSFontManager.shared.traits(of: font).contains(trait)
            attrs[.font] = has
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            return
        }
        if isItalic(attrs) {
            attrs[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
            attrs[.obliqueness] = nil
            if attrs[.mdInline] as? String == "italic" {
                attrs[.mdInline] = nil
            }
            return
        }
        applyItalicStyle(to: &attrs)
    }

    /// True when a run is italic by font trait, synthetic skew, or inline role.
    static func isItalic(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
        if let font = attrs[.font] as? NSFont,
           NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        {
            return true
        }
        if let skew = (attrs[.obliqueness] as? NSNumber)?.doubleValue, skew != 0 {
            return true
        }
        return attrs[.mdInline] as? String == "italic"
    }

    @MainActor
    static func selectedParagraphRange(in textView: NSTextView) -> NSRange {
        let string = textView.string as NSString
        let selected = textView.selectedRange()
        var start = 0
        var end = 0
        string.getParagraphStart(&start, end: &end, contentsEnd: nil, for: selected)
        if end <= start, start < string.length {
            end = string.length
        }
        return NSRange(location: start, length: max(0, end - start))
    }
}

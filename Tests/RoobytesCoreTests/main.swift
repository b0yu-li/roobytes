import AppKit
import Foundation
import RoobytesCore

// Minimal harness — Command Line Tools ship neither XCTest nor Swift Testing.
final class Harness: @unchecked Sendable {
    private var failed = 0
    private var passed = 0

    func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: @autoclosure () -> String = "") {
        if condition() {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            let d = detail()
            print("  ✗ \(name)" + (d.isEmpty ? "" : " — \(d)"))
        }
    }

    func eq<V: Equatable>(_ name: String, _ got: V, _ expected: V) {
        check(name, got == expected, "got \(got), expected \(expected)")
    }

    func finish() -> Int32 {
        print("\n\(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}

private func styled(
    _ markdown: String,
    active: Int? = nil,
    folded: Set<Int> = []
) -> NSAttributedString {
    MarkdownBridge.attributedString(
        from: markdown,
        activeSourceLine: active,
        foldedParentLines: folded
    )
}

private func loc(
    line: Int,
    column: Int,
    in attributed: NSAttributedString,
    markdown: String,
    active: Int? = nil
) -> Int {
    MarkdownBridge.attributedLocation(
        for: MarkdownBridge.MarkdownCaret(line: line, column: column),
        attributed: attributed,
        markdown: markdown,
        activeSourceLine: active
    )
}

private func caret(
    at location: Int,
    in attributed: NSAttributedString,
    markdown: String,
    active: Int? = nil
) -> MarkdownBridge.MarkdownCaret {
    MarkdownBridge.markdownCaret(
        attributedLocation: location,
        attributed: attributed,
        markdown: markdown,
        activeSourceLine: active
    )
}

private func sourceLine(at location: Int, in attributed: NSAttributedString) -> Int? {
    guard attributed.length > 0 else { return nil }
    let probe = min(max(0, location), attributed.length - 1)
    return attributed.attribute(.mdSourceLine, at: probe, effectiveRange: nil) as? Int
}

private let perfEnabled = ProcessInfo.processInfo.environment["OBS_PERF"] == "1"

@discardableResult
private func benchmark(
    _ name: String,
    iterations: Int = 5,
    _ body: () -> Void
) -> Double {
    guard perfEnabled else { return 0 }
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let start = CFAbsoluteTimeGetCurrent()
        body()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        samples.append(elapsed)
    }
    let avg = samples.reduce(0, +) / Double(max(1, samples.count))
    print(String(format: "  • %@: %.2f ms avg (%d runs)", name, avg, iterations))
    return avg
}

let T = Harness()

// MARK: - Blank line / vim `A`

print("Blank line + end-of-line mapping")
do {
    let md = "first\n\nsecond line"
    let attr = styled(md)
    let endCol = ("second line" as NSString).length
    let location = loc(line: 2, column: endCol, in: attr, markdown: md)
    T.eq("source line at end", sourceLine(at: location > 0 ? location - 1 : 0, in: attr), 2)
    let mapped = caret(at: location, in: attr, markdown: md)
    T.eq("caret.line", mapped.line, 2)
    T.eq("caret.column", mapped.column, endCol)
}

do {
    let md = "+ [ ] parent\n\n  + [ ] child"
    let attr = styled(md)
    let line = 2
    let col = ("  + [ ] child" as NSString).length
    let location = loc(line: line, column: col, in: attr, markdown: md)
    let back = caret(at: location, in: attr, markdown: md)
    T.eq("round-trip line", back.line, line)
    T.eq("round-trip column", back.column, col)
}

do {
    let md = "alpha\n\n+ [ ] task body"
    let active = 2
    let attr = styled(md, active: active)
    let col = ("+ [ ] task body" as NSString).length
    let location = loc(line: active, column: col, in: attr, markdown: md, active: active)
    T.check("A-path location in bounds", location <= attr.length)
    let back = caret(at: location, in: attr, markdown: md, active: active)
    T.eq("A-path line", back.line, active)
    T.eq("A-path column", back.column, col)
}

do {
    let md = "a\n\nb"
    let attr = styled(md)
    let ns = attr.string as NSString
    var walk = 0
    var emptyParaSource: Int?
    while walk < ns.length {
        var paraStart = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(
            &paraStart,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: walk, length: 0)
        )
        if contentsEnd == paraStart, paraStart < ns.length {
            emptyParaSource = attr.attribute(
                .mdSourceLine,
                at: paraStart,
                effectiveRange: nil
            ) as? Int
        }
        if end <= walk { break }
        walk = end
    }
    T.eq("empty paragraph mdSourceLine", emptyParaSource, 1)
}

// MARK: - contentStartColumn (vim `I`)

print("\ncontentStartColumn")
T.eq("task open", MarkdownBridge.contentStartColumn(in: "+ [ ] hello"), 6)
T.eq("task focus indented", MarkdownBridge.contentStartColumn(in: "  + [!] focused"), 8)
T.eq("task done", MarkdownBridge.contentStartColumn(in: "- [x] done"), 6)
T.eq("bullet -", MarkdownBridge.contentStartColumn(in: "- item"), 2)
T.eq("bullet +", MarkdownBridge.contentStartColumn(in: "+ item"), 2)
T.eq("bullet nest", MarkdownBridge.contentStartColumn(in: "  * nest"), 4)
T.eq("numbered", MarkdownBridge.contentStartColumn(in: "1. numbered"), 3)
T.eq("numbered wide", MarkdownBridge.contentStartColumn(in: "12. wide"), 4)
T.eq("plain indented", MarkdownBridge.contentStartColumn(in: "  hello"), 2)
T.eq("plain", MarkdownBridge.contentStartColumn(in: "hello"), 0)

print("\nyankableContent")
T.eq("tag only", MarkdownBridge.yankableContent(of: "t: abc"), "abc")
T.eq(
    "task + tag",
    MarkdownBridge.yankableContent(of: "+ [!] t: Spike `usage-service`"),
    "Spike `usage-service`"
)
T.eq("bullet plain", MarkdownBridge.yankableContent(of: "  - plain item"), "plain item")
T.eq("plain line", MarkdownBridge.yankableContent(of: "hello"), "hello")
T.eq("app tag", MarkdownBridge.yankableContent(of: "+ [x] app: Roobytes"), "Roobytes")
T.eq("hyphen slug", MarkdownBridge.yankableContent(of: "+ [ ] wh-os: deploy notes"), "deploy notes")
T.eq("numeric slug", MarkdownBridge.yankableContent(of: "+ [!] 2518: fix caret jump"), "fix caret jump")
T.eq("url kept", MarkdownBridge.yankableContent(of: "+ [ ] https://example.com"), "https://example.com")
T.eq("empty body", MarkdownBridge.yankableContent(of: "+ [ ] "), "")

print("\ntask slug caret helpers")
do {
    let line = "+ [ ] hello"
    // `+ [ ] hello` — slugEnd after `]` (5), bodyStart at `h` (6); multi-space gap snaps forward.
    let gappy = "+ [ ]  hello"
    T.eq("slug end", MarkdownBridge.taskSlugEndOffset(in: line), 5)
    T.eq("body start", MarkdownBridge.taskBodyStartOffset(in: line), 6)
    T.eq("slug interior", MarkdownBridge.taskSlugInteriorOffset(in: line), 3)
    T.eq(
        "gap snaps to body",
        MarkdownBridge.snapTaskCaretOffset(in: gappy, offset: 6),
        7
    )
    T.eq(
        "no snap at body",
        MarkdownBridge.snapTaskCaretOffset(in: line, offset: 6),
        Optional<Int>.none
    )
    T.eq(
        "no snap in slug",
        MarkdownBridge.snapTaskCaretOffset(in: line, offset: 3),
        Optional<Int>.none
    )

    let indented = "  + [ ] nest"
    T.eq("indented slug end", MarkdownBridge.taskSlugEndOffset(in: indented), 7)
    T.eq("indented body start", MarkdownBridge.taskBodyStartOffset(in: indented), 8)
    T.eq("indented slug interior", MarkdownBridge.taskSlugInteriorOffset(in: indented), 5)
    T.eq(
        "indented gap snap",
        MarkdownBridge.snapTaskCaretOffset(in: "  + [ ]  nest", offset: 8),
        9
    )
    T.check("caret in slug", MarkdownBridge.caretIsInTaskSlug(visibleParagraph: line, caretOffset: 3))
    T.check("caret not in body", !MarkdownBridge.caretIsInTaskSlug(visibleParagraph: line, caretOffset: 6))
    T.check(
        "indented caret in slug",
        MarkdownBridge.caretIsInTaskSlug(visibleParagraph: indented, caretOffset: 5)
    )

    T.eq(
        "expand slug col → interior",
        MarkdownBridge.markdownColumnAfterTaskSlugToggle(markdownLine: line, column: 1, expanding: true),
        3
    )
    T.eq(
        "expand body col preserved",
        MarkdownBridge.markdownColumnAfterTaskSlugToggle(markdownLine: line, column: 8, expanding: true),
        8
    )
    T.eq(
        "collapse slug col → body",
        MarkdownBridge.markdownColumnAfterTaskSlugToggle(markdownLine: line, column: 3, expanding: false),
        6
    )
    T.eq(
        "collapse body col preserved",
        MarkdownBridge.markdownColumnAfterTaskSlugToggle(markdownLine: line, column: 8, expanding: false),
        8
    )
    T.eq(
        "expand indented slug",
        MarkdownBridge.markdownColumnAfterTaskSlugToggle(markdownLine: indented, column: 2, expanding: true),
        5
    )
}

print("\ntask checkbox ↔ markdown caret round-trip")
do {
    let md = "+ [ ] wh-os: deploy\nplain\n"
    let bodyStart = MarkdownBridge.contentStartColumn(in: "+ [ ] wh-os: deploy")
    let midBody = bodyStart + 3
    for col in [bodyStart, midBody] {
        let a = styled(md, active: nil)
        let location = loc(line: 0, column: col, in: a, markdown: md, active: nil)
        let back = caret(at: location, in: a, markdown: md, active: nil)
        T.eq("decorated rt col \(col)", back.column, col)
        T.eq("decorated rt line \(col)", back.line, 0)
    }
    let active = styled(md, active: 0)
    let locActive = loc(line: 0, column: midBody, in: active, markdown: md, active: 0)
    let backActive = caret(at: locActive, in: active, markdown: md, active: 0)
    T.eq("active rt col", backActive.column, midBody)
}

print("\ntask checkbox cell (tight)")
do {
    let cell = MarkdownBridge.taskCheckboxCellWidth()
    T.eq("cell = square + gap", cell, 15 + 6)
}

// MARK: - Folds

print("\nNested list folds")
do {
    let lines = [
        "+ [ ] parent",
        "  + [ ] child a",
        "  + [ ] child b",
        "+ [ ] sibling",
    ]
    T.eq("child range", MarkdownBridge.childLineRange(parent: 0, in: lines), 1..<3)
    T.check("can fold parent", MarkdownBridge.canFold(parent: 0, in: lines))
    T.check("cannot fold leaf", !MarkdownBridge.canFold(parent: 1, in: lines))
    T.eq("child count", MarkdownBridge.childCount(parent: 0, in: lines), 2)
}

do {
    let lines = [
        "+ [x] done parent",
        "  + [x] done mid",
        "    + [ ] deep",
        "+ [ ] open parent",
        "  + [ ] open child",
        "+ [x] done leaf",
        "+ [~] deprecated parent",
        "  + [x] under deprecated",
    ]
    let parents = MarkdownBridge.foldableDoneTaskParents(in: lines)
    T.eq("folddone parents", parents, Set([0, 1]))
    T.check("folddone skips open parent", !parents.contains(3))
    T.check("folddone skips done leaf", !parents.contains(5))
    T.check("folddone skips deprecated", !parents.contains(6))
}

do {
    let md = "+ [ ] parent\n  + [ ] child\n+ [ ] after"
    let attr = styled(md, folded: [0])
    let text = attr.string
    T.check("child hidden", !text.contains("child"))
    T.eq("visible line count", text.components(separatedBy: "\n").count, 2)
}

do {
    let md = "+ [ ] parent\n  + [ ] child"
    let attr = styled(md, folded: [0])
    let parentLen = ("+ [ ] parent" as NSString).length
    let location = loc(line: 0, column: parentLen, in: attr, markdown: md)
    let back = caret(at: min(location, max(0, attr.length - 1)), in: attr, markdown: md)
    T.eq("fold cue parent line", back.line, 0)
    T.eq("fold cue parent column", back.column, parentLen)
}

do {
    let md = "+ [ ] parent\n  + [ ] child\n+ [ ] after"
    let attr = styled(md, folded: [0])
    let location = loc(line: 1, column: 0, in: attr, markdown: md)
    T.check("hidden loc in bounds", location >= 0 && location <= attr.length)
    let back = caret(at: min(location, max(0, attr.length - 1)), in: attr, markdown: md)
    T.eq("hidden falls back to parent", back.line, 0)
}

do {
    let lines = [
        "+ [ ] parent",
        "",
        "  + [ ] child a",
        "  + [ ] child b",
        "+ [ ] sibling",
    ]
    let hidden = MarkdownBridge.hiddenLineIndices(foldedParents: [0], lines: lines)
    T.check("fold blank stays", !hidden.contains(1))
    T.check("fold hides child a", hidden.contains(2))
    T.check("fold hides child b", hidden.contains(3))
    T.check("fold keeps sibling", !hidden.contains(4))

    let md = lines.joined(separator: "\n")
    let folded = styled(md, folded: [0])
    T.check("folded view hides child a", !folded.string.contains("child a"))
    T.check("folded view keeps sibling", folded.string.contains("sibling"))
    // Blank separator remains between parent and sibling.
    T.check("folded view keeps blank gap", folded.string.contains("\n\n"))
}

do {
    let folds: Set<Int> = [2, 5]
    T.eq(
        "folds shift on insert above",
        MarkdownBridge.foldsAfterInserting(count: 1, at: 1, into: folds),
        Set([3, 6])
    )
    T.eq(
        "folds keep below insert point",
        MarkdownBridge.foldsAfterInserting(count: 2, at: 4, into: folds),
        Set([2, 7])
    )
    T.eq(
        "folds drop deleted parent",
        MarkdownBridge.foldsAfterDeleting(2..<3, from: folds),
        Set([4])
    )
    T.eq(
        "folds shift after delete below",
        MarkdownBridge.foldsAfterDeleting(0..<1, from: folds),
        Set([1, 4])
    )
    T.eq(
        "folds survive delete of non-parents",
        MarkdownBridge.foldsAfterDeleting(3..<4, from: folds),
        Set([2, 4])
    )
}

do {
    // Folds shift view ordinals — sync must use mdSourceLine, not viewLines[mdIndex].
    let md = """
    + [ ] parent
      + [ ] hidden a
      + [ ] hidden b
    + [!] t: Spike `usage-service`
    + [ ] after

    """
    let attr = styled(md, active: 3, folded: [0])
    let spike = MarkdownBridge.visibleParagraphText(forSourceLine: 3, in: attr)
    T.check("visible spike via source line", spike?.contains("Spike") == true)
    T.check("visible spike is raw when active", spike?.hasPrefix("+ [!]") == true)
    T.check("hidden child not in view", MarkdownBridge.visibleParagraphText(forSourceLine: 1, in: attr) == nil)
    // View ordinal 3 is NOT markdown line 3 once parent children are hidden.
    let viewLines = attr.string.components(separatedBy: "\n")
    T.check("view ordinal diverges under fold", viewLines.count < md.components(separatedBy: "\n").count)
    T.check(
        "viewLines[3] is not spike",
        viewLines.indices.contains(3) ? !viewLines[3].contains("Spike") : true
    )
}

do {
    let md = "+ [ ] parent\n\n  + [ ] nested child\n+ [ ] after"
    let attr = styled(md)
    T.check("render keeps nested after blank", attr.string.contains("nested child"))
    T.check("render keeps blank before nested", attr.string.contains("parent\n\n") || attr.string.contains("\n\n"))
}

// MARK: - Active line sync (stale mdBlock attribute must not block reads)

do {
    // Simulates `o` creating a task line then user deleting the marker.
    // The attributed string still has mdBlock="task" from the original restyle,
    // but the active line (raw source) is now just "+ [" — no valid task prefix.
    // visibleParagraphText must still return the raw content.
    let md = "# Title\n+ [ ] task one\n+ [\n+ [ ] task two"
    let attr = styled(md, active: 2)
    let activeLine = MarkdownBridge.visibleParagraphText(forSourceLine: 2, in: attr)
    T.check("active edited line visible", activeLine != nil)
    T.eq("active edited line content", activeLine ?? "", "+ [")

    // Even when the line is further truncated to just "+", it must be readable.
    let md2 = "# Title\n+ [ ] task one\n+\n+ [ ] task two"
    let attr2 = styled(md2, active: 2)
    let line2 = MarkdownBridge.visibleParagraphText(forSourceLine: 2, in: attr2)
    T.check("active truncated line visible", line2 != nil)
    T.eq("active truncated line content", line2 ?? "", "+")
}

// MARK: - Newline join absorbs next markdown line (no plain duplicate)

do {
    let mdLines = [
        "    + Example.",
        "    + e2e sign-up, stand-up",
        "+ [ ] after",
    ]
    // Simulate joined view: both source lines share one paragraph start.
    let joined = NSMutableAttributedString(
        string: "    + Example.e2e sign-up, stand-up",
        attributes: [.mdSourceLine: 0]
    )
    // Trailing half still tagged as the absorbed neighbor (AppKit keeps attrs on join).
    joined.addAttribute(
        .mdSourceLine,
        value: 1,
        range: NSRange(location: 14, length: joined.length - 14)
    )
    let drop = MarkdownBridge.lineIndexAbsorbedAfterJoin(
        activeLine: 0,
        activeViewText: joined.string,
        markdownLines: mdLines,
        attributed: joined,
        hiddenByFold: []
    )
    T.eq("join drops absorbed e2e neighbor", drop, 1)
    T.check(
        "joined source lines share paragraph",
        MarkdownBridge.sourceLinesShareParagraph(0, 1, in: joined)
    )

    // Separate paragraphs → not a join.
    let separate = NSMutableAttributedString()
    separate.append(NSAttributedString(string: "    + Example.\n", attributes: [.mdSourceLine: 0]))
    separate.append(NSAttributedString(string: "    + e2e sign-up, stand-up", attributes: [.mdSourceLine: 1]))
    let noDrop = MarkdownBridge.lineIndexAbsorbedAfterJoin(
        activeLine: 0,
        activeViewText: "    + Example.",
        markdownLines: mdLines,
        attributed: separate,
        hiddenByFold: []
    )
    T.check("separate paragraphs not absorbed", noDrop == nil)
    T.check(
        "separate source lines do not share paragraph",
        !MarkdownBridge.sourceLinesShareParagraph(0, 1, in: separate)
    )

    // AppKit may discard the absorbed neighbor's source tag entirely.
    let droppedTag = NSAttributedString(
        string: "    + Example.e2e sign-up, stand-up",
        attributes: [.mdSourceLine: 0]
    )
    let droppedTagResult = MarkdownBridge.lineIndexAbsorbedAfterJoin(
        activeLine: 0,
        activeViewText: droppedTag.string,
        markdownLines: mdLines,
        attributed: droppedTag,
        hiddenByFold: []
    )
    T.eq("join detects neighbor with dropped source tag", droppedTagResult, 1)

    // Fold-hidden neighbor must not be dropped.
    let foldDrop = MarkdownBridge.lineIndexAbsorbedAfterJoin(
        activeLine: 0,
        activeViewText: joined.string,
        markdownLines: mdLines,
        attributed: joined,
        hiddenByFold: [1]
    )
    T.check("fold-hidden neighbor kept", foldDrop == nil)

    // Marker-only next line absorbed.
    let markerLines = ["+ body", "    + [ ] ", "after"]
    let markerJoined = NSMutableAttributedString(string: "+ body", attributes: [.mdSourceLine: 0])
    let markerDrop = MarkdownBridge.lineIndexAbsorbedAfterJoin(
        activeLine: 0,
        activeViewText: "+ body",
        markdownLines: markerLines,
        attributed: markerJoined,
        hiddenByFold: []
    )
    T.eq("marker-only neighbor dropped", markerDrop, 1)

    let blankLines = ["+ body", "   ", "after"]
    let blankJoined = NSAttributedString(string: "+ body", attributes: [.mdSourceLine: 0])
    let blankDrop = MarkdownBridge.lineIndexAbsorbedAfterJoin(
        activeLine: 0,
        activeViewText: blankJoined.string,
        markdownLines: blankLines,
        attributed: blankJoined,
        hiddenByFold: []
    )
    T.eq("blank neighbor dropped after join", blankDrop, 1)

    // Backspace join: active absorbed into previous (Esc must not leave orphan line).
    let mergedRaw = MarkdownBridge.markdownAfterBackspaceJoin(
        targetLine: "    + Example.",
        absorbedLine: "e2e sign-up, stand-up",
        joinedViewText: "    + Example.e2e sign-up, stand-up"
    )
    T.eq("backspace join raw view", mergedRaw, "    + Example.e2e sign-up, stand-up")

    let mergedDecorated = MarkdownBridge.markdownAfterBackspaceJoin(
        targetLine: "    + Example.",
        absorbedLine: "e2e sign-up, stand-up",
        joinedViewText: "    • Example.e2e sign-up, stand-up"
    )
    T.eq("backspace join decorated bullet", mergedDecorated, "    + Example.e2e sign-up, stand-up")

    let mergedFallback = MarkdownBridge.markdownAfterBackspaceJoin(
        targetLine: "    + Example.",
        absorbedLine: "    + e2e sign-up",
        joinedViewText: nil
    )
    T.eq("backspace join markdown fallback", mergedFallback, "    + Example. e2e sign-up")

    T.check("decorated checkbox detected", MarkdownBridge.looksLikeDecoratedPreview("  ☐ task"))
    T.check("decorated attachment detected", MarkdownBridge.looksLikeDecoratedPreview("\u{FFFC} task"))
    T.check("raw task is not decorated", !MarkdownBridge.looksLikeDecoratedPreview("+ [ ] task"))
}

// MARK: - Insert sync: emptied active line must persist (Esc must not resurrect)

print("\nInsert sync empty active line")
do {
    // Delete the only character on the active Insert line, then Esc — sync must write ""
    // or restyle resurrects the glyph from stale markdownSource.
    let cleared = MarkdownBridge.insertSyncViewLine(
        activeLine: 8,
        visibleParagraph: "",
        caretParagraphText: "",
        caretSourceLine: 8
    )
    T.eq("cleared tagged paragraph syncs empty", cleared, "")

    let trailingEOF = MarkdownBridge.insertSyncViewLine(
        activeLine: 8,
        visibleParagraph: nil,
        caretParagraphText: "",
        caretSourceLine: nil
    )
    T.eq("character-less trailing empty syncs empty", trailingEOF, "")

    // POSIX trailing `""` after the content line: active is count-2, visible emptied,
    // caret often untagged at EOF — still must clear the active line, not SKIP.
    let posixTrail = MarkdownBridge.insertSyncViewLine(
        activeLine: 7,
        visibleParagraph: "",
        caretParagraphText: "",
        caretSourceLine: nil
    )
    T.eq("emptied line before POSIX trailing empty syncs empty", posixTrail, "")

    let stillTyping = MarkdownBridge.insertSyncViewLine(
        activeLine: 8,
        visibleParagraph: "a",
        caretParagraphText: "a",
        caretSourceLine: 8
    )
    T.eq("non-empty visible wins", stillTyping, "a")

    let caretFallback = MarkdownBridge.insertSyncViewLine(
        activeLine: 3,
        visibleParagraph: nil,
        caretParagraphText: "+ [ ] task",
        caretSourceLine: 3
    )
    T.eq("caret paragraph used when visible absent", caretFallback, "+ [ ] task")

    let wrongCaret = MarkdownBridge.insertSyncViewLine(
        activeLine: 8,
        visibleParagraph: nil,
        caretParagraphText: "",
        caretSourceLine: 7
    )
    T.check("caret on different source line skips", wrongCaret == nil)

    // Visible still has the body — do not clear just because caret wandered.
    let visibleWinsOverWrongCaret = MarkdownBridge.insertSyncViewLine(
        activeLine: 8,
        visibleParagraph: "keep me",
        caretParagraphText: "",
        caretSourceLine: 7
    )
    T.eq("non-empty visible wins even if caret elsewhere", visibleWinsOverWrongCaret, "keep me")
}

do {
    // End-to-end-ish: active last line "a", then a view with that paragraph emptied.
    let md = "# Focus\n\n# Notes\n\na"
    let lines = md.components(separatedBy: "\n")
    let active = lines.count - 1
    T.eq("fixture last line is a", lines[active], "a")

    let before = styled(md, active: active)
    T.eq(
        "before delete visible is a",
        MarkdownBridge.visibleParagraphText(forSourceLine: active, in: before),
        "a"
    )
    T.eq(
        "before delete sync keeps a",
        MarkdownBridge.insertSyncViewLine(
            activeLine: active,
            visibleParagraph: MarkdownBridge.visibleParagraphText(forSourceLine: active, in: before),
            caretParagraphText: "a",
            caretSourceLine: active
        ),
        "a"
    )

    // Simulate the post-backspace view: same document without the final glyph.
    let afterMd = String(md.dropLast())
    let after = styled(afterMd + (afterMd.hasSuffix("\n") ? "" : ""), active: active)
    // Active index may still point at the last content slot; view line is empty / trailing.
    let afterVisible = MarkdownBridge.visibleParagraphText(forSourceLine: active, in: after)
    let afterCaretSrc = MarkdownBridge.sourceLine(atCaretLocation: after.length, in: after)
    let synced = MarkdownBridge.insertSyncViewLine(
        activeLine: active,
        visibleParagraph: afterVisible,
        caretParagraphText: "",
        caretSourceLine: afterCaretSrc
    )
    T.eq("after delete sync clears stale a", synced, "")
}

// MARK: - Trailing empty last line (bottom-of-document edits)

print("\nTrailing empty last line")
do {
    // `o` at EOF then backspacing the `+ ` empties the last line. That paragraph owns no
    // characters, so the caret must not resolve to the previous line — doing so made sync
    // read a backspace-join, delete the last line, and eat a character from the line above.
    let md = "+ [ ] parent\n+ ...\n"
    let lines = md.components(separatedBy: "\n")
    let last = lines.count - 1
    T.eq("trailing empty line index", last, 2)

    let attr = styled(md, active: last)
    let eof = attr.length
    T.check(
        "caret at EOF is in trailing empty paragraph",
        MarkdownBridge.caretInTrailingEmptyParagraph(caretLocation: eof, in: attr)
    )
    T.check(
        "trailing empty caret has no source line",
        MarkdownBridge.sourceLine(atCaretLocation: eof, in: attr) == nil
    )
    T.check(
        "trailing empty line absent from view",
        MarkdownBridge.visibleParagraphStart(forSourceLine: last, in: attr) == nil
    )
    T.check(
        "trailing empty line does not share paragraph with previous",
        !MarkdownBridge.sourceLinesShareParagraph(last, last - 1, in: attr)
    )
    // Editing the line above must not silently drop the empty last line.
    T.check(
        "trailing empty line kept while newline stands",
        MarkdownBridge.lineIndexAbsorbedAfterJoin(
            activeLine: last - 1,
            activeViewText: "+ ...",
            markdownLines: lines,
            attributed: attr,
            hiddenByFold: []
        ) == nil
    )
}

do {
    // Caret at the end of a normal (non-empty) last line still maps to that line.
    let md = "+ a\n+ b"
    let attr = styled(md, active: 1)
    T.check(
        "EOF without trailing newline is not an empty paragraph",
        !MarkdownBridge.caretInTrailingEmptyParagraph(caretLocation: attr.length, in: attr)
    )
    T.eq("caret at EOF maps to last line", MarkdownBridge.sourceLine(atCaretLocation: attr.length, in: attr), 1)
    T.eq("caret at line start maps to that line", MarkdownBridge.sourceLine(atCaretLocation: 0, in: attr), 0)
}

do {
    // A middle empty line owns its terminating newline, so it stays resolvable.
    let md = "+ a\n\n+ c"
    let attr = styled(md, active: 0)
    let blankStart = MarkdownBridge.visibleParagraphStart(forSourceLine: 1, in: attr)
    T.check("middle empty line present in view", blankStart != nil)
    T.eq(
        "caret in middle empty line maps to it",
        MarkdownBridge.sourceLine(atCaretLocation: blankStart ?? 0, in: attr),
        1
    )
}

do {
    // Genuine forward-delete at EOF removes the final newline — then the empty last line
    // really was absorbed and must be dropped.
    let lines = ["+ a", "+ b", ""]
    let joined = styled("+ a\n+ b", active: 1)
    T.eq(
        "absorbed trailing empty line dropped",
        MarkdownBridge.lineIndexAbsorbedAfterJoin(
            activeLine: 1,
            activeViewText: "+ b",
            markdownLines: lines,
            attributed: joined,
            hiddenByFold: []
        ),
        2
    )
}

do {
    // Normal-mode caret must not rest on the glyph-less trailing empty after a final `\n`.
    let md = "# Focus\n+ [ ] task\n"
    let attr = styled(md, active: nil)
    let eof = attr.length
    T.check(
        "sample ends in trailing empty paragraph",
        MarkdownBridge.caretInTrailingEmptyParagraph(caretLocation: eof, in: attr)
    )
    let clamped = MarkdownBridge.caretLocationClampedOffTrailingEmpty(
        caretLocation: eof,
        in: attr
    )
    T.check("clamp leaves trailing empty", clamped < eof)
    T.check(
        "clamp lands on last real paragraph",
        MarkdownBridge.sourceLine(atCaretLocation: clamped, in: attr) != nil
    )

    let lines = md.components(separatedBy: "\n")
    T.eq("POSIX split has trailing empty", lines.last, "")
    T.eq(
        "G skips absent trailing empty",
        MarkdownBridge.lastNavigableMarkdownLineIndex(in: lines, attributed: attr),
        lines.count - 2
    )
}

do {
    // Intentional empty last line (`content\n\n`) stays navigable for G.
    let md = "+ a\n\n"
    let attr = styled(md, active: nil)
    let lines = md.components(separatedBy: "\n")
    // ["+ a", "", ""] — last "" is POSIX artifact; middle "" is a real blank line.
    T.eq(
        "G lands on intentional blank",
        MarkdownBridge.lastNavigableMarkdownLineIndex(in: lines, attributed: attr),
        1
    )
}

print("\nLineIndexCache trailing newline")
do {
    var cache = LineIndexCache()
    cache.rebuildForced(from: "a\nb\n")
    T.eq("a\\nb\\n is two lines", cache.lineCount, 2)
    T.eq("EOF maps to last content line", cache.lineIndex(at: 4), 1)

    cache.rebuildForced(from: "a\nb\n\n")
    T.eq("a\\nb\\n\\n keeps blank line", cache.lineCount, 3)
    T.eq("blank line start", cache.characterIndex(forLine: 2), 4)
}

// MARK: - FuzzyMatcher / frecency

do {
    T.check("fuzzy empty query", FuzzyMatcher.score(query: "", target: "Gaps") == 0)
    T.check("fuzzy subsequence", FuzzyMatcher.score(query: "gp", target: "Gaps") != nil)
    T.check("fuzzy miss", FuzzyMatcher.score(query: "xyz", target: "Gaps") == nil)
    let pathHit = FuzzyMatcher.score(query: "dg", target: "diaries/Gaps")
    let pathWeak = FuzzyMatcher.score(query: "dg", target: "dodgy")
    T.check("fuzzy path boundary preferred", (pathHit ?? -1) > (pathWeak ?? -1))
}

do {
    let now = Date()
    let recent = FileHistoryStore.frecency(
        openCount: 2,
        lastOpened: now.addingTimeInterval(-3600),
        now: now,
        halfLifeHours: 168
    )
    let stale = FileHistoryStore.frecency(
        openCount: 10,
        lastOpened: now.addingTimeInterval(-3600 * 24 * 60),
        now: now,
        halfLifeHours: 168
    )
    T.check("recent beats stale high-count", recent > stale)
    let hot = FileHistoryStore.frecency(
        openCount: 5,
        lastOpened: now,
        now: now,
        halfLifeHours: 168
    )
    let cool = FileHistoryStore.frecency(
        openCount: 1,
        lastOpened: now,
        now: now,
        halfLifeHours: 168
    )
    T.check("higher count wins when equal age", hot > cool)
}

do {
    let vault = URL(fileURLWithPath: "/tmp/vault-test", isDirectory: true)
    let a = vault.appendingPathComponent("Gaps.md")
    let b = vault.appendingPathComponent("diaries/note.md")
    T.eq("rel root", VaultFileIndex.relativeDisplayPath(for: a, vault: vault), "Gaps")
    T.eq("rel nested", VaultFileIndex.relativeDisplayPath(for: b, vault: vault), "diaries/note")
}

// MARK: - Focus dim

do {
    let md = "intro\n+ [!] focus me\nother"
    T.eq("focus line index", MarkdownBridge.focusTaskLineIndex(inMarkdown: md), 1)
    let attr = styled(md)
    // First glyph of "intro" should be strongly dimmed (tertiary); focus line keeps wash.
    let introColor = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    T.check("intro strongly dimmed", introColor == RoobytesTheme.editorTertiary)
    let focusLoc = loc(line: 1, column: 0, in: attr, markdown: md)
    let wash = attr.attribute(.backgroundColor, at: min(focusLoc, max(0, attr.length - 1)), effectiveRange: nil)
    T.check("focus wash present", wash != nil)
    let noFocus = styled("intro\n+ [ ] open\nother")
    let bright = noFocus.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    T.check("no focus no dim", bright != RoobytesTheme.editorSecondary || bright == nil || bright == RoobytesTheme.editorForeground)
}

// MARK: - Strikethrough contrast

do {
    let done = styled("+ [x] finished task")
    let bodyLoc = (done.string as NSString).range(of: "finished task").location
    T.eq(
        "done task thin strike",
        done.attribute(.strikethroughStyle, at: bodyLoc, effectiveRange: nil) as? Int,
        NSUnderlineStyle.single.rawValue
    )
    T.check(
        "done task bright strike",
        done.attribute(.strikethroughColor, at: bodyLoc, effectiveRange: nil) as? NSColor
            == RoobytesTheme.editorForeground
    )

    let inline = styled("before ~~removed~~ after")
    let inlineLoc = (inline.string as NSString).range(of: "removed").location
    T.eq(
        "inline thin strike",
        inline.attribute(.strikethroughStyle, at: inlineLoc, effectiveRange: nil) as? Int,
        NSUnderlineStyle.single.rawValue
    )
}

// MARK: - Word under caret (K / Look Up)

do {
    T.eq("word mid", WordUnderCaret.word(in: "say hello there", column: 6), "hello")
    T.eq("word start", WordUnderCaret.word(in: "say hello there", column: 4), "hello")
    T.eq("word end char", WordUnderCaret.word(in: "say hello there", column: 8), "hello")
    T.eq("word boundary left", WordUnderCaret.word(in: "say hello", column: 9), "hello")
    T.check("no word on space", WordUnderCaret.word(in: "say hello", column: 3) == nil)
    T.eq("hyphenated", WordUnderCaret.word(in: "pre-commit hooks", column: 2), "pre-commit")
    T.eq("inside md bold markers", WordUnderCaret.word(in: "**hello**", column: 3), "hello")
    let range = WordUnderCaret.range(in: "say hello" as NSString, at: 6)
    T.eq("range loc", range?.location, 4)
    T.eq("range len", range?.length, 5)
}

// MARK: - URL under caret

do {
    let sheets = "see https://docs.google.com/spreadsheets/d/abc123/edit#gid=0 today"
    let sheetsURL = URL(string: "https://docs.google.com/spreadsheets/d/abc123/edit#gid=0")
    let mid = (sheets as NSString).range(of: "spreadsheets").location
    T.eq("bare sheets mid", URLUnderCaret.url(in: sheets, column: mid), sheetsURL)
    T.eq("bare sheets start", URLUnderCaret.url(in: sheets, column: 4), sheetsURL) // on 'h' of https
    T.check("no url", URLUnderCaret.url(in: "plain text only", column: 3) == nil)

    let punct = "link https://example.com/path)."
    T.eq(
        "strip trailing punct",
        URLUnderCaret.url(in: punct, column: 10),
        URL(string: "https://example.com/path")
    )

    let mdLink = "read [Sheet](https://docs.google.com/spreadsheets/d/xyz) now"
    let linkURL = URL(string: "https://docs.google.com/spreadsheets/d/xyz")
    let labelCol = (mdLink as NSString).range(of: "Sheet").location
    let urlCol = (mdLink as NSString).range(of: "docs.google").location
    T.eq("md link on label", URLUnderCaret.url(in: mdLink, column: labelCol), linkURL)
    T.eq("md link on url", URLUnderCaret.url(in: mdLink, column: urlCol), linkURL)
    T.check("md link outside", URLUnderCaret.url(in: mdLink, column: 0) == nil)

    let http = "go http://example.com/a"
    T.eq("http scheme", URLUnderCaret.url(in: http, column: 5), URL(string: "http://example.com/a"))

    let ranges = URLUnderCaret.httpURLRanges(in: sheets)
    T.eq("url ranges count", ranges.count, 1)
    T.eq("url range text", (sheets as NSString).substring(with: ranges[0]), sheetsURL!.absoluteString)

    let styledURL = styled("https://www.notion.so\n")
    let linkColor = styledURL.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    T.check("bare url not body color", linkColor != nil && linkColor != RoobytesTheme.editorForeground)
    let underline = styledURL.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
    T.check("bare url underline", underline == NSUnderlineStyle.single.rawValue)
    let inlineRole = styledURL.attribute(.mdInline, at: 0, effectiveRange: nil) as? String
    T.eq("bare url mdInline", inlineRole, "link")

    let mdStyled = styled("see [Sheet](https://docs.google.com/spreadsheets/d/xyz) now")
    let labelLoc = (mdStyled.string as NSString).range(of: "Sheet").location
    T.check("md label link", labelLoc != NSNotFound)
    if labelLoc != NSNotFound {
        let role = mdStyled.attribute(.mdInline, at: labelLoc, effectiveRange: nil) as? String
        T.eq("md label mdInline", role, "link")
    }
}

// MARK: - #tag highlight

do {
    let ranges = TagHighlight.ranges(in: "• #idea Demo to shorten")
    T.eq("tag count", ranges.count, 1)
    T.eq("tag text", ("• #idea Demo to shorten" as NSString).substring(with: ranges[0]), "#idea")
    T.eq("no tag in heading ticks", TagHighlight.ranges(in: "### Title").count, 0)
    T.eq("no tag after word", TagHighlight.ranges(in: "foo#bar").count, 0)
    T.eq("nested tag", TagHighlight.ranges(in: "see #work/focus today").count, 1)
    T.eq("no tag for ordinal", TagHighlight.ranges(in: "take #1 for example").count, 0)
    T.eq("no tag for multi-digit ordinal", TagHighlight.ranges(in: "issue #2026 filed").count, 0)
    T.eq("digits with letter still a tag", TagHighlight.ranges(in: "ship #v2 today").count, 1)
    T.eq("dated tag", TagHighlight.ranges(in: "log #2026-07-29 entry").count, 1)
    T.eq(
        "nested text",
        ("see #work/focus today" as NSString).substring(with: TagHighlight.ranges(in: "see #work/focus today")[0]),
        "#work/focus"
    )

    let styledTag = styled("+ #idea Demo line\n")
    let tagLoc = (styledTag.string as NSString).range(of: "#idea").location
    T.check("tag in view", tagLoc != NSNotFound)
    if tagLoc != NSNotFound {
        let role = styledTag.attribute(.mdInline, at: tagLoc, effectiveRange: nil) as? String
        T.eq("tag mdInline", role, "tag")
        let color = styledTag.attribute(.foregroundColor, at: tagLoc, effectiveRange: nil) as? NSColor
        T.check("tag not body color", color != nil && color != RoobytesTheme.editorForeground)
    }
}

// MARK: - Time range duration

do {
    T.eq(
        "93 minutes",
        TimeRangeDuration.insertion(afterTypingOpenParenIn: "10:00 - 11:33 ("),
        "93')"
    )
    T.eq(
        "60 minutes",
        TimeRangeDuration.insertion(afterTypingOpenParenIn: "10:30 - 11:30 ("),
        "60')"
    )
    T.eq(
        "tight spacing",
        TimeRangeDuration.insertion(afterTypingOpenParenIn: "9:05-10:05("),
        "60')"
    )
    T.eq(
        "overnight",
        TimeRangeDuration.insertion(afterTypingOpenParenIn: "23:30 - 00:15 ("),
        "45')"
    )
    T.check(
        "not a range",
        TimeRangeDuration.insertion(afterTypingOpenParenIn: "hello (") == nil
    )
    T.check(
        "invalid hour",
        TimeRangeDuration.insertion(afterTypingOpenParenIn: "25:00 - 26:00 (") == nil
    )
}

// MARK: - Vim help / ex

do {
    T.eq("resolve :h", VimExCommand.resolve("h")?.canonical, "h")
    T.eq("resolve :help", VimExCommand.resolve("help")?.canonical, "h")
    T.eq("resolve :tips", VimExCommand.resolve("tips")?.canonical, "tips")
    T.eq("resolve :tip", VimExCommand.resolve("tip")?.canonical, "tips")
    T.eq("resolve :complete", VimExCommand.resolve("complete")?.canonical, "complete")
    T.eq("resolve :cmp", VimExCommand.resolve("cmp")?.canonical, "complete")
    T.eq("resolve :autocomplete", VimExCommand.resolve("autocomplete")?.canonical, "complete")
    T.eq("resolve :daily", VimExCommand.resolve("daily")?.canonical, "daily")
    T.eq("resolve :today", VimExCommand.resolve("today")?.canonical, "daily")
    T.eq("resolve :folddone", VimExCommand.resolve("folddone")?.canonical, "folddone")
    T.eq("resolve :fd", VimExCommand.resolve("fd")?.canonical, "folddone")
    T.eq("complete :fo", VimExCommand.completion(forPrefix: "fo"), "folddone")
    T.check("help text has Esc", VimHelp.text.contains("Esc"))
    T.check("help text has gx", VimHelp.text.contains("gx"))
    T.check("help text has K", VimHelp.text.contains("K"))
    T.check("help text has z=", VimHelp.text.contains("z="))
    T.check("help text has md", VimHelp.text.contains("md"))
    T.check("help text has ]t", VimHelp.text.contains("]t"))
    T.check("help text has mD", VimHelp.text.contains("mD"))
    T.check("help text has :w", VimHelp.text.contains(":w"))
    T.check("help text has v Visual", VimHelp.text.contains("Visual"))
    T.check("help text has Visual yank", VimHelp.text.contains("y yank"))
    T.check("help text has Visual cut", VimHelp.text.contains("d/x cut"))
    T.check("help text has ⇧Tab", VimHelp.text.contains("⇧Tab"))
    T.check("help Edit lists Visual y d x", VimHelp.sections.contains(where: {
        $0.title == "Edit" && $0.rows.contains(where: { $0.keys == "y d x" })
    }))
    T.check("help text has gj gk", VimHelp.text.contains("gj gk"))
    T.check("help notes wrapped rows", VimHelp.text.contains("wrapped row"))
    T.check(
        "help Modes lists v",
        VimHelp.sections.contains(where: {
            $0.title == "Modes" && $0.rows.contains(where: { $0.keys == "v" })
        })
    )
    T.check("help lists itself", VimHelp.text.contains(":h"))
    T.check("help lists :tips", VimHelp.text.contains(":tips"))
    T.check("help lists :complete", VimHelp.text.contains(":complete"))
    T.check("help lists :daily", VimHelp.text.contains(":daily"))
    T.check("help lists :folddone", VimHelp.text.contains(":folddone"))
    T.check("help mentions q close", VimHelp.subtitle.contains("q"))
    T.check("help subtitle has ⌃e", VimHelp.subtitle.contains("⌃e"))
    T.check("help subtitle has ⌃y", VimHelp.subtitle.contains("⌃y"))
    T.check("help subtitle has ⌃d", VimHelp.subtitle.contains("⌃d"))
    T.eq("help section count", VimHelp.sections.count, 8)
    T.check("help has Tasks", VimHelp.sections.contains(where: { $0.title == "Tasks" }))
    T.check("help Edit lists Look Up", VimHelp.sections.contains(where: {
        $0.title == "Edit" && $0.rows.contains(where: { $0.keys == "K" })
    }))
    T.check("tips has list-indent", RoobytesTips.all.contains(where: { $0.id == "list-indent" }))
    T.check("tips catalog non-empty", !RoobytesTips.all.isEmpty)
    T.check("tips has daily-note", RoobytesTips.all.contains(where: { $0.id == "daily-note" }))
    T.check("tips daily mentions folder", RoobytesTips.all.contains(where: {
        $0.id == "daily-note" && $0.body.contains("diaries")
    }))
    T.check("help :daily mentions template prompt", VimHelp.text.contains("prompts if template"))
    T.check("tips has lookup-k", RoobytesTips.all.contains(where: { $0.id == "lookup-k" }))
    T.check("tips has visual-select", RoobytesTips.all.contains(where: { $0.id == "visual-select" }))
    T.check("tips visual mentions yank", RoobytesTips.all.contains(where: {
        $0.id == "visual-select" && $0.body.contains("yanks")
    }))
    T.check("tips folds mention folddone", RoobytesTips.all.contains(where: {
        $0.id == "folds" && $0.body.contains(":folddone")
    }))
    let avoided = RoobytesTips.all[0].id
    for _ in 0..<20 {
        T.check("tips random avoids last", RoobytesTips.random(avoiding: avoided).id != avoided)
    }
}

// MARK: - Characterwise Visual selection range

do {
    T.eq(
        "visual same endpoint",
        VimVisual.selectionRange(anchor: 5, caret: 5, documentLength: 20),
        NSRange(location: 5, length: 1)
    )
    T.eq(
        "visual extend right",
        VimVisual.selectionRange(anchor: 5, caret: 8, documentLength: 20),
        NSRange(location: 5, length: 4)
    )
    T.eq(
        "visual extend left",
        VimVisual.selectionRange(anchor: 8, caret: 5, documentLength: 20),
        NSRange(location: 5, length: 4)
    )
    T.eq(
        "visual empty doc",
        VimVisual.selectionRange(anchor: 0, caret: 0, documentLength: 0),
        NSRange(location: 0, length: 0)
    )
    T.eq(
        "visual caret at end",
        VimVisual.selectionRange(anchor: 3, caret: 10, documentLength: 10),
        NSRange(location: 3, length: 7)
    )
}

// MARK: - Characterwise Visual slice / delete / insert

do {
    let a = MarkdownBridge.MarkdownCaret(line: 0, column: 1)
    let b = MarkdownBridge.MarkdownCaret(line: 0, column: 3)
    let lines = ["abcd", "ef", "ghij"]
    T.eq("char slice same line", VimCharacterwise.slice(from: a, through: b, in: lines), "bcd")
    T.eq(
        "char slice multi",
        VimCharacterwise.slice(
            from: MarkdownBridge.MarkdownCaret(line: 0, column: 2),
            through: MarkdownBridge.MarkdownCaret(line: 2, column: 1),
            in: lines
        ),
        "cd\nef\ngh"
    )

    let deleted = VimCharacterwise.deleting(from: a, through: b, in: lines)
    // Inclusive columns 1…3 of "abcd" remove "bcd".
    T.eq("char delete same line", deleted.lines, ["a", "ef", "ghij"])
    T.eq("char delete caret", deleted.caret, MarkdownBridge.MarkdownCaret(line: 0, column: 1))

    let multiDel = VimCharacterwise.deleting(
        from: MarkdownBridge.MarkdownCaret(line: 0, column: 2),
        through: MarkdownBridge.MarkdownCaret(line: 2, column: 1),
        in: lines
    )
    T.eq("char delete multi merge", multiDel.lines, ["abij"])
    T.eq("char delete multi caret", multiDel.caret, MarkdownBridge.MarkdownCaret(line: 0, column: 2))
    T.eq(
        "char delete line range",
        VimCharacterwise.deletedLineRange(
            from: MarkdownBridge.MarkdownCaret(line: 0, column: 2),
            through: MarkdownBridge.MarkdownCaret(line: 2, column: 1)
        ),
        1..<3
    )

    let inserted = VimCharacterwise.inserting(
        "XY",
        at: MarkdownBridge.MarkdownCaret(line: 0, column: 2),
        in: ["abcd"]
    )
    T.eq("char insert same line", inserted.lines, ["abXYcd"])
    T.eq("char insert caret start", inserted.caret, MarkdownBridge.MarkdownCaret(line: 0, column: 2))

    let multiIns = VimCharacterwise.inserting(
        "X\nY",
        at: MarkdownBridge.MarkdownCaret(line: 0, column: 2),
        in: ["abcd"]
    )
    T.eq("char insert multi", multiIns.lines, ["abX", "Ycd"])
}

// MARK: - Vertical motion: display rows vs logical lines

do {
    T.check("bare j walks display rows", VimVerticalMotion.usesDisplayRows(hasCount: false, gPrefixed: false))
    // `5j` must stay logical: the gutter numbers count logical lines.
    T.check("counted j stays logical", !VimVerticalMotion.usesDisplayRows(hasCount: true, gPrefixed: false))
    T.check("gj forces display rows", VimVerticalMotion.usesDisplayRows(hasCount: false, gPrefixed: true))
    T.check("3gj forces display rows", VimVerticalMotion.usesDisplayRows(hasCount: true, gPrefixed: true))
}

// MARK: - Task checkbox caret ring geometry

do {
    // 15pt square in a 21pt cell (square + trailing gap), sitting 3pt below baseline.
    let bounds = CGRect(x: 0, y: -3, width: 21, height: 15)
    let square = TaskCheckboxCaret.squareRect(
        fragmentOrigin: CGPoint(x: 0, y: 40),
        glyphLocation: CGPoint(x: 5, y: 18),
        attachmentBounds: bounds,
        containerOrigin: CGPoint(x: 8, y: 6)
    )
    // TextKit reports the attachment bottom (40 + 18), not the baseline: top = 43.
    // Treating the location as a baseline would yield y = 52 and ring the box too low.
    T.eq("checkbox caret square", square, CGRect(x: 13, y: 49, width: 15, height: 15))
    T.eq("checkbox caret drops trailing gap", square.width, bounds.height)
}

// MARK: - Daily notes

do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 28))!
    T.eq("daily fileName", DailyNotes.fileName(for: date, calendar: cal), "2026-07-28.md")
    T.eq("daily stem", DailyNotes.dateStem(for: date, calendar: cal), "2026-07-28")

    let fm = FileManager.default
    let vault = fm.temporaryDirectory.appendingPathComponent("roobytes-daily-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: vault) }
    try! fm.createDirectory(at: vault, withIntermediateDirectories: true)
    let diaries = DailyNotes.diariesFolder(vault: vault)
    try! fm.createDirectory(at: diaries, withIntermediateDirectories: true)

    // Prefer exact over emoji sibling.
    let exact = diaries.appendingPathComponent("2026-07-28.md")
    let emoji = diaries.appendingPathComponent("2026-07-28 ☁️.md")
    try! "# emoji\n".write(to: emoji, atomically: true, encoding: .utf8)
    try! "# exact\n".write(to: exact, atomically: true, encoding: .utf8)
    T.eq(
        "prefer exact daily",
        DailyNotes.existingNoteURL(vault: vault, date: date, calendar: cal, fileManager: fm)?.lastPathComponent,
        "2026-07-28.md"
    )
    try! fm.removeItem(at: exact)
    T.eq(
        "fallback emoji daily",
        DailyNotes.existingNoteURL(vault: vault, date: date, calendar: cal, fileManager: fm)?.lastPathComponent,
        "2026-07-28 ☁️.md"
    )
    try! fm.removeItem(at: emoji)

    // Missing template → error.
    do {
        _ = try DailyNotes.ensureTodaysNote(vault: vault, date: date, calendar: cal, fileManager: fm)
        T.check("missing template should throw", false)
    } catch DailyNotes.EnsureError.templateMissing {
        T.check("missing template", true)
    } catch {
        T.check("missing template wrong error", false)
    }

    T.check("templateExists false", !DailyNotes.templateExists(vault: vault, fileManager: fm))

    // Install starter, then create from it.
    try! DailyNotes.installStarterTemplate(vault: vault, fileManager: fm)
    T.check("templateExists after starter", DailyNotes.templateExists(vault: vault, fileManager: fm))
    let starterURL = DailyNotes.templateURL(vault: vault)
    T.eq(
        "starter body",
        try! String(contentsOf: starterURL, encoding: .utf8),
        DailyNotes.starterTemplateMarkdown
    )
    let created = try! DailyNotes.ensureTodaysNote(vault: vault, date: date, calendar: cal, fileManager: fm)
    T.eq("created name", created.lastPathComponent, "2026-07-28.md")
    T.eq(
        "created body",
        try! String(contentsOf: created, encoding: .utf8),
        DailyNotes.starterTemplateMarkdown
    )

    // Auto-create diaries folder when absent.
    let vault2 = fm.temporaryDirectory.appendingPathComponent("roobytes-daily2-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: vault2) }
    try! fm.createDirectory(at: vault2, withIntermediateDirectories: true)
    try! DailyNotes.installStarterTemplate(vault: vault2, fileManager: fm)
    T.check("diaries absent before", !DailyNotes.diariesFolderExists(vault: vault2, relativePath: "diaries", fileManager: fm))
    let created2 = try! DailyNotes.ensureTodaysNote(
        vault: vault2,
        date: date,
        calendar: cal,
        fileManager: fm,
        relativePath: "diaries"
    )
    T.check("diaries auto-created", DailyNotes.diariesFolderExists(vault: vault2, relativePath: "diaries", fileManager: fm))
    T.check("note in diaries", created2.path.contains("/diaries/"))
    T.eq("sanitize nested", DailyNotes.sanitizeDiariesRelativePath("notes/daily"), "notes/daily")
    T.eq("sanitize reject ..", DailyNotes.sanitizeDiariesRelativePath("../x"), Optional<String>.none)
    _ = try! DailyNotes.ensureDiariesFolder(vault: vault2, relativePath: "journal", fileManager: fm)
    T.check("custom folder", DailyNotes.diariesFolderExists(vault: vault2, relativePath: "journal", fileManager: fm))

    // Second call reopens existing (no duplicate).
    let again = try! DailyNotes.ensureTodaysNote(vault: vault, date: date, calendar: cal, fileManager: fm)
    T.eq("reopen same", again.path, created.path)

    // Copy-install overwrites template.
    let other = vault.appendingPathComponent("other-template.md")
    let otherBody = "## Copied\n+ [ ] from pick\n"
    try! otherBody.write(to: other, atomically: true, encoding: .utf8)
    try! DailyNotes.installTemplate(copying: other, vault: vault, fileManager: fm)
    T.eq(
        "copy install body",
        try! String(contentsOf: DailyNotes.templateURL(vault: vault), encoding: .utf8),
        otherBody
    )
}

// MARK: - Heading accent colors

do {
    let md = "# H1\n## H2\n### H3\n#### H4\nbody"
    let attr = styled(md)
    func color(atNeedle needle: String) -> NSColor? {
        let loc = (attr.string as NSString).range(of: needle).location
        guard loc != NSNotFound else { return nil }
        return attr.attribute(.foregroundColor, at: loc, effectiveRange: nil) as? NSColor
    }
    let h1 = color(atNeedle: "H1")
    let h2 = color(atNeedle: "H2")
    let h3 = color(atNeedle: "H3")
    let h4 = color(atNeedle: "H4")
    T.check("h1 body-ish", h1 == RoobytesTheme.editorForeground || h1 != nil)
    T.check("h2 accent-ish", h2 != nil && h2 != RoobytesTheme.editorForeground)
    T.check("h3 distinct from h2", h3 != nil && h3 != h2)
    T.check("h4 distinct from h3", h4 != nil && h4 != h3)
    T.check("h4 distinct from h2", h4 != h2)

    // Focus dim must not wash h2–h4 accents (Normal / Live Preview).
    let withFocus = styled(
        "## TPN Tracker\n+ [!] focus me\n## Log\n### Nested",
    )
    let tpnLoc = (withFocus.string as NSString).range(of: "TPN").location
    let logLoc = (withFocus.string as NSString).range(of: "Log").location
    T.check("focus dim keeps h2", tpnLoc != NSNotFound)
    if tpnLoc != NSNotFound {
        let c = withFocus.attribute(.foregroundColor, at: tpnLoc, effectiveRange: nil) as? NSColor
        T.check("h2 not dimmed to secondary", c != RoobytesTheme.editorSecondary)
    }
    if logLoc != NSNotFound {
        let c = withFocus.attribute(.foregroundColor, at: logLoc, effectiveRange: nil) as? NSColor
        T.check("second h2 not dimmed", c != RoobytesTheme.editorSecondary)
    }
}

// MARK: - Vim chord hints (context-aware pending keys)

do {
    let bare = VimChordHints.entries(for: "g", context: .init())
    T.eq("g bare keys", bare.map(\.keys), ["gg", "gj gk"])

    let withURL = VimChordHints.entries(
        for: "g",
        context: .init(hasURLUnderCaret: true)
    )
    T.eq("g with URL", withURL.map(\.keys), ["gg", "gj gk", "gx", "gX"])

    let r = VimChordHints.entries(for: "r", context: .init())
    T.eq("r hint", r.map(\.keys), ["r{char}"])

    let y = VimChordHints.entries(for: "y", context: .init())
    T.eq("y hint", y.map(\.keys), ["yy"])

    let bracketNext = VimChordHints.entries(for: "]", context: .init())
    T.eq("] hint", bracketNext.map(\.keys), ["]t"])
    let bracketPrev = VimChordHints.entries(for: "[", context: .init())
    T.eq("[ hint", bracketPrev.map(\.keys), ["[t"])

    let zFold = VimChordHints.entries(
        for: "z",
        context: .init(canFold: true, isFolded: false)
    )
    T.eq("z foldable", zFold.map(\.keys), ["z=", "zz", "za", "zc"])

    let zOpen = VimChordHints.entries(
        for: "z",
        context: .init(canFold: true, isFolded: true)
    )
    T.eq("z folded", zOpen.map(\.keys), ["z=", "zz", "za", "zo"])

    let display = VimChordHints.display(pending: "g", count: 3, context: .init(hasURLUnderCaret: true))
    T.check("display head has count", display.hasPrefix("3g · waiting"))
    T.check("display lists gx", display.contains("gx"))

    let mHints = VimChordHints.entries(
        for: "m",
        context: .init(canToggleFocus: true, canMarkTaskDone: true, canMarkTaskOpen: false)
    )
    T.eq("m keys", mHints.map(\.keys), ["md", "mD", "mf"])
    T.check("m md active blurb", mHints[0].blurb.contains("[x]"))
    T.check("m mD inactive blurb", mHints[1].blurb.contains("need done"))
}

// MARK: - Task mark done / open (md / mD)

do {
    T.eq("md from open", MarkdownBridge.markTaskDone(in: "- [ ] buy"), "- [x] buy")
    T.eq("md from focus", MarkdownBridge.markTaskDone(in: "- [!] buy"), "- [x] buy")
    T.eq("md from deprecated", MarkdownBridge.markTaskDone(in: "- [~] buy"), "- [x] buy")
    T.check("md already done", MarkdownBridge.markTaskDone(in: "- [x] buy") == nil)

    T.eq("mD from done", MarkdownBridge.markTaskOpen(in: "- [x] buy"), "- [ ] buy")
    T.eq("mD from focus", MarkdownBridge.markTaskOpen(in: "- [!] buy"), "- [ ] buy")
    T.eq("mD from deprecated", MarkdownBridge.markTaskOpen(in: "- [~] buy"), "- [ ] buy")
    T.check("mD already open", MarkdownBridge.markTaskOpen(in: "- [ ] buy") == nil)
    T.check("md not a task", MarkdownBridge.markTaskDone(in: "plain") == nil)
}

// MARK: - Undone task motion (]t / [t)

do {
    let lines = [
        "+ [x] done",
        "+ [ ] open a",
        "plain",
        "+ [!] focus",
        "+ [~] deprecated",
        "+ [ ] open b",
    ]
    T.eq("undone indices", MarkdownBridge.undoneTaskLineIndices(in: lines), [1, 3, 5])
    T.eq("]t from top", MarkdownBridge.nextUndoneTaskLine(from: -1, in: lines), 1)
    T.eq("]t skip self", MarkdownBridge.nextUndoneTaskLine(from: 1, in: lines), 3)
    T.eq("]t skip done+plain", MarkdownBridge.nextUndoneTaskLine(from: 0, in: lines), 1)
    T.eq("2]t", MarkdownBridge.nextUndoneTaskLine(from: 0, count: 2, in: lines), 3)
    T.eq("3]t", MarkdownBridge.nextUndoneTaskLine(from: 0, count: 3, in: lines), 5)
    T.check("]t past end", MarkdownBridge.nextUndoneTaskLine(from: 5, in: lines) == nil)
    T.check("3]t from mid fails", MarkdownBridge.nextUndoneTaskLine(from: 1, count: 3, in: lines) == nil)
    T.eq("[t from bottom", MarkdownBridge.previousUndoneTaskLine(from: 6, in: lines), 5)
    T.eq("[t skip self", MarkdownBridge.previousUndoneTaskLine(from: 5, in: lines), 3)
    T.eq("2[t", MarkdownBridge.previousUndoneTaskLine(from: 5, count: 2, in: lines), 1)
    T.check("[t past start", MarkdownBridge.previousUndoneTaskLine(from: 1, in: lines) == nil)
}

// MARK: - Parent / child task helpers

do {
    let lines = [
        "- [ ] Parent",          // 0
        "  - [ ] Child 1",       // 1
        "  - [x] Child 2",       // 2
        "  - [ ] Child 3",       // 3
    ]
    T.eq("parent of child 1", MarkdownBridge.parentTaskLineIndex(of: 1, in: lines), 0)
    T.eq("parent of child 3", MarkdownBridge.parentTaskLineIndex(of: 3, in: lines), 0)
    T.check("no parent for root", MarkdownBridge.parentTaskLineIndex(of: 0, in: lines) == nil)
    T.eq("direct children of 0", MarkdownBridge.directChildTaskLineIndices(of: 0, in: lines), [1, 2, 3])
}

do {
    let lines = [
        "- [ ] Grandparent",    // 0
        "  - [ ] Parent",       // 1
        "    - [x] Child A",    // 2
        "    - [ ] Child B",    // 3
        "  - [x] Uncle",        // 4
    ]
    T.eq("parent of child A", MarkdownBridge.parentTaskLineIndex(of: 2, in: lines), 1)
    T.eq("parent of parent", MarkdownBridge.parentTaskLineIndex(of: 1, in: lines), 0)
    T.eq("direct children of 1", MarkdownBridge.directChildTaskLineIndices(of: 1, in: lines), [2, 3])
    T.eq("direct children of 0", MarkdownBridge.directChildTaskLineIndices(of: 0, in: lines), [1, 4])
}

do {
    // Non-task structural parent → nil
    let lines = [
        "- plain bullet",       // 0
        "  - [ ] Child",        // 1
    ]
    T.check("non-task parent", MarkdownBridge.parentTaskLineIndex(of: 1, in: lines) == nil)
}

// MARK: - Cascade: all sub-tasks done → parent done

do {
    var lines = [
        "- [ ] Parent",
        "  - [x] Child 1",
        "  - [ ] Child 2",
    ]
    // Toggle child 2 done → all children done → parent should become done
    lines[2] = MarkdownBridge.markTaskDone(in: lines[2])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 2, in: &lines)
    T.eq("cascade marks parent done", lines[0], "- [x] Parent")
    T.eq("cascade modified indices", modified, [0])
}

// MARK: - Cascade: sub-task undone → parent undone

do {
    var lines = [
        "- [x] Parent",
        "  - [x] Child 1",
        "  - [x] Child 2",
    ]
    // Mark child 1 open → parent should become open
    lines[1] = MarkdownBridge.markTaskOpen(in: lines[1])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 1, in: &lines)
    T.eq("cascade marks parent open", lines[0], "- [ ] Parent")
    T.eq("cascade modified (undone)", modified, [0])
}

// MARK: - Cascade: multi-level

do {
    var lines = [
        "- [ ] Grandparent",
        "  - [ ] Parent",
        "    - [x] Child 1",
        "    - [ ] Child 2",
    ]
    lines[3] = MarkdownBridge.markTaskDone(in: lines[3])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 3, in: &lines)
    T.eq("multi-level parent done", lines[1], "  - [x] Parent")
    T.eq("multi-level grandparent done", lines[0], "- [x] Grandparent")
    T.eq("multi-level modified", modified, [1, 0])
}

do {
    var lines = [
        "- [x] Grandparent",
        "  - [x] Parent",
        "    - [x] Child 1",
        "    - [x] Child 2",
    ]
    lines[2] = MarkdownBridge.markTaskOpen(in: lines[2])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 2, in: &lines)
    T.eq("multi-level parent undone", lines[1], "  - [ ] Parent")
    T.eq("multi-level grandparent undone", lines[0], "- [ ] Grandparent")
    T.eq("multi-level undone modified", modified, [1, 0])
}

// MARK: - Cascade: newly created open child → parent undone

do {
    var lines = [
        "+ [x] Parent",
        "  + [x] Child 1",
        "  + [ ] Child 2", // newly created open task
    ]
    let modified = MarkdownBridge.reconcileTaskTree(around: 2, in: &lines)
    T.eq("new child reopens parent", lines[0], "+ [ ] Parent")
    T.eq("new child modified parent", modified, [0])
}

// MARK: - Cascade: bullets between parent and children still cascade

do {
    var lines = [
        "+ [x] Parent",
        "  + cite: note",
        "  + [x] Done child",
        "  + [ ] Open child",
    ]
    let modified = MarkdownBridge.reconcileTaskTree(around: 3, in: &lines)
    T.eq("bullets intervening: parent opens", lines[0], "+ [ ] Parent")
    T.eq("bullets intervening: modified", modified, [0])
}

// MARK: - Cascade: md on parent with open child reopens parent

do {
    var lines = [
        "+ [ ] Parent",
        "  + [ ] Open child",
    ]
    lines[0] = MarkdownBridge.markTaskDone(in: lines[0])!
    let modified = MarkdownBridge.reconcileTaskTree(around: 0, in: &lines)
    T.eq("md parent with open kid → reopen", lines[0], "+ [ ] Parent")
    T.eq("md parent with open kid modified", modified, [0])
}

// MARK: - Cascade: deprecated counts as resolved

do {
    var lines = [
        "- [ ] Parent",
        "  - [~] Deprecated child",
        "  - [ ] Open child",
    ]
    lines[2] = MarkdownBridge.markTaskDone(in: lines[2])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 2, in: &lines)
    T.eq("deprecated + done → parent done", lines[0], "- [x] Parent")
    T.eq("deprecated cascade modified", modified, [0])
}

// MARK: - Cascade: partial completion (no cascade)

do {
    var lines = [
        "- [ ] Parent",
        "  - [ ] Child 1",
        "  - [ ] Child 2",
        "  - [ ] Child 3",
    ]
    lines[1] = MarkdownBridge.markTaskDone(in: lines[1])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 1, in: &lines)
    T.eq("partial: parent stays open", lines[0], "- [ ] Parent")
    T.eq("partial: no modified", modified, [Int]())
}

// MARK: - Cascade: no children → no cascade

do {
    var lines = [
        "- [ ] Solo task",
    ]
    lines[0] = MarkdownBridge.markTaskDone(in: lines[0])!
    let modified = MarkdownBridge.cascadeParentTaskState(afterToggling: 0, in: &lines)
    T.eq("solo: no cascade", modified, [Int]())
}

// MARK: - Line syntax helpers

do {
    T.eq(
        "continue task",
        MarkdownBridge.listContinuationPrefix(for: "  + [x] done item"),
        "  + [ ] "
    )
    T.eq(
        "continue bullet",
        MarkdownBridge.listContinuationPrefix(for: "- item"),
        "- "
    )
    T.eq(
        "continue numbered",
        MarkdownBridge.listContinuationPrefix(for: "  3. third"),
        "  1. "
    )
    T.eq(
        "continue plain",
        MarkdownBridge.listContinuationPrefix(for: "  plain"),
        "  "
    )

    T.check("isList task", MarkdownBridge.isListLine("+ [ ] x"))
    T.check("isList bullet", MarkdownBridge.isListLine("  - item"))
    T.check("isList numbered", MarkdownBridge.isListLine("1. a"))
    T.check("isList plain false", !MarkdownBridge.isListLine("  plain"))
    T.eq(
        "indent nest",
        MarkdownBridge.adjustListIndent("+ [ ] root", delta: 1),
        "  + [ ] root"
    )
    T.eq(
        "outdent nest",
        MarkdownBridge.adjustListIndent("  + [ ] nest", delta: -1),
        "+ [ ] nest"
    )
    T.eq(
        "outdent root nil",
        MarkdownBridge.adjustListIndent("+ [ ] root", delta: -1),
        Optional<String>.none
    )
    T.eq(
        "indent bullet",
        MarkdownBridge.adjustListIndent("- item", delta: 1),
        "  - item"
    )

    T.eq("heading body h3", MarkdownBridge.headingBody("### Title"), "Title")
    T.eq("heading body indented", MarkdownBridge.headingBody("  ## Nested"), "Nested")
    T.check("heading body plain", MarkdownBridge.headingBody("plain") == nil)

    let h2 = "## Hello"
    T.eq("heading marker len", MarkdownBridge.headingMarkerLength(h2), 3)
    T.eq(
        "heading marker indented",
        MarkdownBridge.headingMarkerLength("  # Hi"),
        4
    )
    T.check("heading marker plain", MarkdownBridge.headingMarkerLength("Hi") == nil)
}

// MARK: - Serializer round-trip (styled → markdown)

do {
    func roundTrip(_ markdown: String, active: Int? = nil) -> String {
        MarkdownBridge.markdown(from: styled(markdown, active: active))
    }

    T.eq(
        "rt headings",
        roundTrip("# H1\n## H2\n### H3\n#### H4"),
        "# H1\n## H2\n### H3\n#### H4"
    )
    // Bullet markers normalize to `+`.
    T.eq("rt bullet plus", roundTrip("+ item"), "+ item")
    T.eq("rt bullet dash→plus", roundTrip("- item"), "+ item")
    T.eq("rt numbered", roundTrip("1. item"), "1. item")

    T.eq("rt task open", roundTrip("+ [ ] open"), "+ [ ] open")
    T.eq("rt task done", roundTrip("+ [x] done"), "+ [x] done")
    T.eq("rt task focus", roundTrip("+ [!] focus"), "+ [!] focus")
    T.eq("rt task deprecated", roundTrip("+ [~] old"), "+ [~] old")
    T.eq("rt task indent", roundTrip("  + [ ] nested"), "  + [ ] nested")

    T.eq("rt blank lines", roundTrip("alpha\n\nbeta"), "alpha\n\nbeta")
    T.eq("rt quote", roundTrip("> quoted"), "> quoted")
    T.eq("rt paragraph", roundTrip("just text"), "just text")

    // Inline markers: bold / code survive; italic often drops (PT Mono has no italic trait).
    T.eq(
        "rt inline bold+code",
        roundTrip("hello **bold** and `code`"),
        "hello **bold** and `code`"
    )
    T.check(
        "rt inline keeps bold",
        roundTrip("hello **bold** and *italic* and `code`").contains("**bold**")
    )
    T.check(
        "rt inline keeps code",
        roundTrip("hello **bold** and *italic* and `code`").contains("`code`")
    )
    T.check(
        "rt underscore italic → *…*",
        roundTrip("hello _italic_ world").contains("*italic*")
    )
    T.check(
        "rt underscore italic keeps phrase",
        roundTrip(#"cite: _the pattern you "learned"._"#).contains("*the pattern")
    )

    // Active source line stays raw (including heading hashes / task slug).
    T.eq(
        "rt active heading",
        roundTrip("# Live\nbody", active: 0),
        "# Live\nbody"
    )
    T.eq(
        "rt active task",
        roundTrip("intro\n+ [ ] raw task", active: 1),
        "intro\n+ [ ] raw task"
    )
}

// MARK: - Underscore italic render + caret

do {
    let star = styled("say *hello* there")
    T.eq("star italic strips markers", star.string, "say hello there")
    let starRole = star.attribute(
        .mdInline,
        at: (star.string as NSString).range(of: "hello").location,
        effectiveRange: nil
    ) as? String
    T.eq("star italic mdInline", starRole, "italic")

    let under = styled("say _hello_ there")
    T.eq("under italic strips markers", under.string, "say hello there")
    let underRole = under.attribute(
        .mdInline,
        at: (under.string as NSString).range(of: "hello").location,
        effectiveRange: nil
    ) as? String
    T.eq("under italic mdInline", underRole, "italic")

    let phrase = styled(#"cite: _the pattern you "learned" is best._"#)
    T.check(
        "phrase italic no raw underscores",
        !phrase.string.contains("_")
    )
    T.check(
        "phrase italic visible body",
        phrase.string.contains(#"the pattern you "learned" is best."#)
    )

    let snake = styled("use snake_case names")
    T.eq("snake_case stays literal", snake.string, "use snake_case names")

    // Regression: a transformed NSFont renders at 1pt (invisible text). Italic must keep
    // body point size and monospace advances — only the skew differs.
    let italicLoc = (under.string as NSString).range(of: "hello").location
    if let bodyFont = under.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
       let italicFont = under.attribute(.font, at: italicLoc, effectiveRange: nil) as? NSFont
    {
        T.eq("italic keeps point size", italicFont.pointSize, bodyFont.pointSize)
        let plainWidth = NSAttributedString(string: "hello", attributes: [.font: bodyFont]).size().width
        let italicWidth = NSAttributedString(string: "hello", attributes: [.font: italicFont]).size().width
        T.check(
            "italic run stays visible width",
            abs(italicWidth - plainWidth) < 0.5,
            "italic \(italicWidth) vs plain \(plainWidth)"
        )
        let skew = under.attribute(.obliqueness, at: italicLoc, effectiveRange: nil) as? NSNumber
        let hasRealItalic = NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask)
        T.check(
            "italic is slanted (trait or skew)",
            hasRealItalic || (skew?.doubleValue ?? 0) != 0
        )
    } else {
        T.check("italic fonts present", false)
    }

    let md = "say _hello_ there"
    let attr = styled(md)
    // Column 6 = 'h' of `_hello_` in source → visible "hello"
    let location = loc(line: 0, column: 6, in: attr, markdown: md)
    let back = caret(at: location, in: attr, markdown: md)
    T.eq("under italic caret line", back.line, 0)
    T.eq("under italic caret col", back.column, 6)
    let endBack = caret(at: loc(line: 0, column: md.utf16.count, in: attr, markdown: md), in: attr, markdown: md)
    T.eq("under italic caret end", endBack.column, md.utf16.count)
}

// MARK: - Buffer word index / insert autocomplete

do {
    var index = BufferWordIndex()
    index.rebuild(from: "hello world\nhello there\nworldwide")

    T.eq("word index unique count", index.count, 4)
    T.eq(
        "word tokenize hyphen",
        BufferWordIndex.tokenize("pre-commit and foo_bar"),
        ["pre-commit", "and", "foo_bar"]
    )

    T.check(
        "min prefix length 2",
        index.candidates(matchingPrefix: "h").isEmpty
    )
    T.eq(
        "prefix he → hello",
        index.candidates(matchingPrefix: "he"),
        ["hello"]
    )
    T.eq(
        "prefix th → there",
        index.candidates(matchingPrefix: "th"),
        ["there"]
    )
    T.eq(
        "exclude current full word",
        index.candidates(matchingPrefix: "th", excluding: "there"),
        []
    )

    var related = BufferWordIndex()
    related.rebuild(from: "alpha alphabet alpine")
    T.eq(
        "exclude keeps longer siblings",
        related.candidates(matchingPrefix: "alp", excluding: "alpha"),
        ["alphabet", "alpine"]
    )
    T.eq(
        "prefix wo → longer first",
        index.candidates(matchingPrefix: "wo"),
        ["worldwide"]
    )
    T.check(
        "short world dropped when worldwide exists",
        !index.candidates(matchingPrefix: "wo").contains("world")
    )
    T.check(
        "exact word alone not suggested",
        index.candidates(matchingPrefix: "hello", excluding: "hello").isEmpty
    )

    var hard = BufferWordIndex()
    hard.rebuild(from: "sum such successful suddenly well")
    T.eq(
        "prefer long hard words",
        hard.candidates(matchingPrefix: "su"),
        ["successful", "suddenly"]
    )
    T.eq(
        "displayForm keeps typed case",
        BufferWordIndex.displayForm(candidate: "well", prefix: "We"),
        "Well"
    )

    T.eq(
        "ghost suffix",
        BufferWordIndex.ghostSuffix(candidate: "hello", prefix: "he"),
        "llo"
    )
    T.check(
        "ghost nil when exact",
        BufferWordIndex.ghostSuffix(candidate: "hi", prefix: "hi") == nil
    )

    if let at = BufferWordIndex.prefixAtCaret(line: "say hello", utf16Column: 5) {
        // "say h|" — prefix "h"
        T.eq("prefixAtCaret mid word start", at.prefix, "h")
        T.eq("prefixAtCaret startUTF16", at.startUTF16, 4)
    } else {
        T.check("prefixAtCaret mid word start", false)
    }

    if let at = BufferWordIndex.prefixAtCaret(line: "say hello", utf16Column: 9) {
        T.eq("prefixAtCaret full hello", at.prefix, "hello")
    } else {
        T.check("prefixAtCaret full hello", false)
    }
    T.check(
        "prefixAtCaret after space",
        BufferWordIndex.prefixAtCaret(line: "say ", utf16Column: 4) == nil
    )

    T.eq(
        "fullWordAtCaret middle",
        BufferWordIndex.fullWordAtCaret(line: "say hello there", utf16Column: 6),
        "hello"
    )

    // Cap unique words.
    var capped = BufferWordIndex()
    let many = (0..<5_000).map { "w\($0)" }.joined(separator: " ")
    capped.rebuild(from: many)
    T.eq("word index cap", capped.count, BufferWordIndex.maxUniqueWords)

    // Case: first-seen spelling kept; match is case-insensitive.
    var cased = BufferWordIndex()
    cased.rebuild(from: "Markdown markdown MARK")
    T.eq("case first-seen", cased.count, 2)
    T.eq(
        "case insensitive prefix",
        cased.candidates(matchingPrefix: "mark"),
        ["Markdown"]
    )
}

print("\nSource-line paragraph index")
do {
    let md = """
    - parent
      - child one
      - child two
    tail
    """
    let attr = styled(md, folded: [0])
    let index = MarkdownBridge.buildSourceLineParagraphIndex(in: attr)

    let parentViaIndex = MarkdownBridge.visibleParagraphStart(
        forSourceLine: 0,
        in: attr,
        sourceLineParagraphIndex: index
    )
    let parentViaScan = MarkdownBridge.visibleParagraphStart(forSourceLine: 0, in: attr)
    T.eq("index parent start matches scan", parentViaIndex, parentViaScan)

    let hiddenViaIndex = MarkdownBridge.visibleParagraphStart(
        forSourceLine: 1,
        in: attr,
        sourceLineParagraphIndex: index
    )
    T.eq("index keeps hidden as nil", hiddenViaIndex, nil)

    let line3 = MarkdownBridge.visibleParagraphText(
        forSourceLine: 3,
        in: attr,
        sourceLineParagraphIndex: index
    )
    T.eq("index visible tail", line3, "tail")
}

print("\nLarge document caret mapping")
do {
    let lines = (0..<1_000).map { "line-\($0) body **bold** `code`" }
    let md = lines.joined(separator: "\n")
    let attr = styled(md)
    let allLines = md.components(separatedBy: "\n")

    for i in stride(from: 0, to: lines.count, by: 57) {
        let line = lines[i]
        let col = min(8, (line as NSString).length)
        let location = loc(line: i, column: col, in: attr, markdown: md)
        let mapped = MarkdownBridge.markdownCaret(
            attributedLocation: location,
            attributed: attr,
            markdown: md,
            activeSourceLine: nil,
            markdownLines: allLines
        )
        T.eq("large rt line \(i)", mapped.line, i)
        T.eq("large rt col \(i)", mapped.column, col)
    }
}

if perfEnabled {
    print("\nPerf (OBS_PERF=1)")
    let lines = (0..<1_000).map { "task \($0): + [ ] body **bold** `code` #tag\($0)" }
    let md = lines.joined(separator: "\n")
    let markdownLines = md.components(separatedBy: "\n")
    benchmark("render_full_1000") {
        _ = styled(md)
    }
    let attr = styled(md)
    benchmark("caret_round_trip_1000x") {
        for i in 0..<1_000 {
            let line = i % markdownLines.count
            let text = markdownLines[line]
            let col = min(10, (text as NSString).length)
            let location = MarkdownBridge.attributedLocation(
                for: MarkdownBridge.MarkdownCaret(line: line, column: col),
                attributed: attr,
                markdown: md,
                activeSourceLine: nil,
                markdownLines: markdownLines
            )
            _ = MarkdownBridge.markdownCaret(
                attributedLocation: location,
                attributed: attr,
                markdown: md,
                activeSourceLine: nil,
                markdownLines: markdownLines
            )
        }
    }
}

exit(T.finish())

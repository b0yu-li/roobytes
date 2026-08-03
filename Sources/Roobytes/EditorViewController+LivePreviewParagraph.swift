import AppKit

@MainActor
extension EditorViewController {
    func currentParagraphText() -> String {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: sel)
        return ns.substring(with: NSRange(location: start, length: max(0, contentsEnd - start)))
    }

    func caretOffsetInParagraph() -> Int {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: sel)
        return sel.location - start
    }

    func setCaretOffsetInParagraph(_ offset: Int) {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: sel)
        textView.setSelectedRange(NSRange(location: start + offset, length: 0))
    }
}

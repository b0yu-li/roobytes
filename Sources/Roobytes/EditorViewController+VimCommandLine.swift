import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    private func vimChordHintContext() -> VimChordHints.Context {
        let lines = markdownLines
        let caret = currentMarkdownCaret()
        let line = (caret.line >= 0 && caret.line < lines.count) ? lines[caret.line] : ""
        let hasURL = URLUnderCaret.url(in: line, column: caret.column) != nil
        let canFold = MarkdownBridge.canFold(parent: caret.line, in: lines)
        let isFolded = foldedParentLines.contains(caret.line)
        let hasFocus = MarkdownBridge.focusTaskLineIndex(in: lines) != nil
        return VimChordHints.Context(
            hasURLUnderCaret: hasURL,
            canToggleFocus: canToggleFocusTask,
            canMarkTaskDone: canMarkTaskDone,
            canMarkTaskOpen: canMarkTaskOpen,
            hasFocusTask: hasFocus,
            canFold: canFold,
            isFolded: isFolded
        )
    }

    func showVimChordHints(for pending: Character) {
        hideVimHelp()
        if vimCommandLine != nil {
            endVimCommandLine()
        }
        isVimChordHintVisible = true
        let body = VimChordHints.display(
            pending: pending,
            count: vimCount,
            context: vimChordHintContext()
        )
        RoobytesDebugLog.event("chord hint \(pending) count=\(vimCount)")
        setCommandPalettePosition(.bottomTrailing)
        showCommandPalette(asMessage: true)
        commandPalette.configureWrapping()
        commandPalette.setAttributedText(attributedVimChordHint(body))
        resizeCommandPaletteForMultiline(body, fontSize: 13, minWidth: 220, maxWidth: 360)
    }

    func hideVimChordHint() {
        guard isVimChordHintVisible else { return }
        isVimChordHintVisible = false
        if vimCommandLine == nil, !isVimHelpVisible, !isTipVisible {
            resetCommandPaletteLayout()
            commandPalette.hide()
        }
    }

    private func attributedVimChordHint(_ body: String) -> NSAttributedString {
        let font = RoobytesFont.regular(size: 13)
        let mono = RoobytesFont.regular(size: 13)
        let result = NSMutableAttributedString()
        let lines = body.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            if i == 0 {
                result.append(
                    NSAttributedString(
                        string: line,
                        attributes: [
                            .font: font,
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ]
                    )
                )
                continue
            }
            // "  gg  Top of file" — accent the keys column.
            let trimmed = line.drop(while: { $0 == " " })
            let leading = line.count - trimmed.count
            if leading > 0 {
                result.append(NSAttributedString(string: String(repeating: " ", count: leading)))
            }
            let rest = String(trimmed)
            if let gap = rest.firstIndex(of: " ") {
                let keys = String(rest[..<gap])
                let blurb = String(rest[gap...]).trimmingCharacters(in: .whitespaces)
                result.append(
                    NSAttributedString(
                        string: keys,
                        attributes: [
                            .font: mono,
                            .foregroundColor: RoobytesAccent.bright,
                        ]
                    )
                )
                result.append(
                    NSAttributedString(
                        string: "  " + blurb,
                        attributes: [
                            .font: font,
                            .foregroundColor: NSColor.labelColor,
                        ]
                    )
                )
            } else {
                result.append(
                    NSAttributedString(
                        string: rest,
                        attributes: [
                            .font: font,
                            .foregroundColor: NSColor.labelColor,
                        ]
                    )
                )
            }
        }
        return result
    }
    // MARK: - Vim command line (`:w` / `:q` / `:pin`)

    func beginVimCommandLine() {
        hideVimHelp()
        hideTip()
        hideWordCompletion()
        clearVimPrefix()
        delegate?.editorWillBeginCommandPalette(self)
        vimCommandLine = ":"
        setCommandPalettePosition(.topCenter)
        commandPalette.configureSingleLine(truncatingHead: true)
        refreshCommandPaletteInput()
        showCommandPalette(asMessage: false)
    }

    func endVimCommandLine() {
        vimCommandLine = nil
        if !isVimHelpVisible, !isTipVisible, !isVimChordHintVisible {
            resetCommandPaletteLayout()
            commandPalette.hide()
        }
    }

    func handleVimCommandLineKey(_ event: NSEvent) -> Bool {
        if Self.isEscapeEvent(event) {
            endVimCommandLine()
            return true
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            return true
        }

        if event.keyCode == 36 || event.keyCode == 76 { // Return / keypad Enter
            commitVimCommandLine()
            return true
        }

        if event.keyCode == 48 { // Tab — accept autocomplete
            acceptVimCommandCompletion()
            return true
        }

        if event.keyCode == 51 { // Delete
            guard var buf = vimCommandLine, buf.count > 1 else {
                endVimCommandLine()
                return true
            }
            buf.removeLast()
            vimCommandLine = buf
            refreshCommandPaletteInput()
            return true
        }

        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return true }
        for ch in chars where ch.isASCII && !ch.isNewline {
            if ch == Character(UnicodeScalar(8)!) { continue }
            vimCommandLine = (vimCommandLine ?? ":") + String(ch)
        }
        refreshCommandPaletteInput()
        return true
    }

    private func acceptVimCommandCompletion() {
        let typed = commandBody(from: vimCommandLine ?? ":")
        guard let full = VimExCommand.completion(forPrefix: typed) else { return }
        vimCommandLine = ":" + full
        refreshCommandPaletteInput()
    }

    private func commandBody(from buffer: String) -> String {
        let trimmed = buffer.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(":") ? String(trimmed.dropFirst()) : trimmed
    }

    private func refreshCommandPaletteInput() {
        let buffer = vimCommandLine ?? ":"
        let body = commandBody(from: buffer)
        let font = RoobytesFont.regular(size: 15)
        let display = NSMutableAttributedString(
            string: buffer,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        if let ghost = VimExCommand.ghostSuffix(forPrefix: body), !ghost.isEmpty {
            display.append(
                NSAttributedString(
                    string: ghost,
                    attributes: [
                        .font: font,
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                )
            )
        }
        commandPalette.setAttributedText(display)
        let fullWidthText = buffer + (VimExCommand.ghostSuffix(forPrefix: body) ?? "")
        resizeCommandPalette(for: fullWidthText.isEmpty ? ":" : fullWidthText)
    }

    private func commitVimCommandLine() {
        let raw = (vimCommandLine ?? "").trimmingCharacters(in: .whitespaces)
        let body = commandBody(from: raw)

        // If incomplete but uniquely completable, accept the match (vim-ish).
        let resolvedBody: String
        if VimExCommand.resolve(body) != nil {
            resolvedBody = body
        } else if let completed = VimExCommand.completion(forPrefix: body) {
            resolvedBody = completed
        } else {
            resolvedBody = body
        }

        endVimCommandLine()

        guard !resolvedBody.isEmpty else { return }
        guard let command = VimExCommand.resolve(resolvedBody) else {
            flashCommandLineMessage("Not an editor command: \(resolvedBody)")
            NSSound.beep()
            return
        }

        switch command {
        case .write:
            let wrote = delegate?.editorRequestSave(self) ?? false
            if wrote {
                flashCommandLineMessage("Written")
            }
        case .quit:
            delegate?.editorRequestQuit(self)
        case .pin:
            let pinned = delegate?.editorRequestTogglePin(self) ?? false
            flashCommandLineMessage(pinned ? "Pinned" : "Unpinned")
        case .discard:
            if let message = delegate?.editorRequestDiscard(self) {
                flashCommandLineMessage(message)
            }
        case .help:
            RoobytesDebugLog.event("ex :help")
            showVimHelp()
        case .tips:
            RoobytesDebugLog.event("ex :tips")
            showTip()
        case .complete:
            let on = !RoobytesSettings.shared.wordCompletion
            RoobytesSettings.shared.wordCompletion = on
            if !on { hideWordCompletion() }
            RoobytesDebugLog.event("ex :complete → \(on ? "on" : "off")")
            flashCommandLineMessage(on ? "Complete on" : "Complete off")
        case .daily:
            RoobytesDebugLog.event("ex :daily")
            if let message = delegate?.editorRequestDailyNote(self) {
                flashCommandLineMessage(message)
                NSSound.beep()
            }
        case .folddone:
            let count = foldAllDoneTasks()
            RoobytesDebugLog.event("ex :folddone → \(count)")
            if count == 0 {
                flashCommandLineMessage("No done tasks to fold")
                NSSound.beep()
            } else {
                flashCommandLineMessage(count == 1 ? "Folded 1 done task" : "Folded \(count) done tasks")
            }
        }
    }

    private func showVimHelp() {
        RoobytesDebugLog.event("help show")
        hideVimChordHint()
        hideTip()
        isVimHelpVisible = true
        let attributed = VimHelp.attributedText()
        setCommandPalettePosition(.center)
        applyCommandPaletteChrome(message: true)
        commandPalette.configureWrapping()
        commandPalette.setAttributedText(attributed)
        resizeCommandPaletteForHelp(attributed)
        commandPalette.show(withScrim: true)
    }

    func hideVimHelp() {
        guard isVimHelpVisible else { return }
        RoobytesDebugLog.event("help hide")
        isVimHelpVisible = false
        if !isVimChordHintVisible, !isTipVisible {
            resetCommandPaletteLayout()
            commandPalette.hide()
        }
    }

    func showTip() {
        hideVimChordHint()
        hideVimHelp()
        if vimCommandLine != nil {
            endVimCommandLine()
        }
        let tip = RoobytesTips.random(avoiding: RoobytesSettings.shared.lastTipID)
        RoobytesSettings.shared.lastTipID = tip.id
        RoobytesDebugLog.event("tip show id=\(tip.id)")
        isTipVisible = true
        let attributed = RoobytesTips.attributedText(for: tip)
        setCommandPalettePosition(.topCenter)
        showCommandPalette(asMessage: true)
        commandPalette.configureWrapping()
        commandPalette.setAttributedText(attributed)
        resizeCommandPaletteForMultiline(
            attributed.string,
            fontSize: 13,
            minWidth: 360,
            maxWidth: 480
        )
    }

    func hideTip() {
        guard isTipVisible else { return }
        RoobytesDebugLog.event("tip hide")
        isTipVisible = false
        if !isVimChordHintVisible, !isVimHelpVisible {
            resetCommandPaletteLayout()
            commandPalette.hide()
        }
    }

    func flashCommandLineMessage(_ message: String) {
        hideVimHelp()
        hideTip()
        hideVimChordHint()
        setCommandPalettePosition(.topCenter)
        showCommandPalette(asMessage: true)
        commandPalette.configureSingleLine(truncatingHead: false)
        commandPalette.setAttributedText(
            NSAttributedString(
                string: message,
                attributes: [
                    .font: RoobytesFont.regular(size: 14),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        )
        resizeCommandPalette(for: message)
        if message == "Written" {
            celebrateWritten()
            TypewriterSound.shared.playWrite()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self,
                  self.vimCommandLine == nil,
                  !self.isVimHelpVisible,
                  !self.isTipVisible,
                  !self.isVimChordHintVisible
            else { return }
            self.commandPalette.hide()
            self.resetCommandPaletteLayout()
        }
    }

    private func celebrateWritten() {
        view.layoutSubtreeIfNeeded()
        ConfettiCelebration.burst(in: view, at: commandPalette.anchorPoint(in: view))
    }
    private func showCommandPalette(asMessage: Bool) {
        applyCommandPaletteChrome(message: asMessage)
        commandPalette.show()
    }

    func applyCommandPaletteChrome(message: Bool) {
        let style: EditorCommandPalette.Style
        let fontSize: CGFloat
        let alignment: NSTextAlignment
        if isVimHelpVisible {
            style = .help
            fontSize = 12.5
            alignment = .left
        } else if isVimChordHintVisible || isTipVisible {
            style = .panel
            fontSize = 13
            alignment = .left
        } else if message {
            style = .flash
            fontSize = 14
            alignment = .center
        } else {
            style = .quiet
            fontSize = 15
            alignment = .left
        }
        commandPalette.applyChrome(style: style, labelFontSize: fontSize, alignment: alignment)
    }

    private func resizeCommandPalette(for text: String) {
        commandPalette.resizeForSingleLine(text)
    }

    private func resizeCommandPaletteForMultiline(
        _ text: String,
        fontSize: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) {
        commandPalette.resizeForMultiline(
            text,
            fontSize: fontSize,
            minWidth: minWidth,
            maxWidth: maxWidth
        )
    }

    private func resizeCommandPaletteForHelp(_ attributed: NSAttributedString) {
        commandPalette.resizeForHelp(attributed)
    }

    private func resetCommandPaletteLayout() {
        commandPalette.resetLayout()
    }

    private func setCommandPalettePosition(_ position: EditorCommandPalette.Placement) {
        commandPalette.setPlacement(position)
    }
}

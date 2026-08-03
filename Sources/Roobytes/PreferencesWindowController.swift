import AppKit

/// Settings window (⌘,).
@MainActor
final class PreferencesWindowController: NSWindowController {
    private let appearanceControl = NSSegmentedControl(
        labels: AppearancePreference.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let accentStack = NSStackView()
    private var accentSwatches: [AccentSwatchButton] = []
    private let reopenCheckbox = NSButton(
        checkboxWithTitle: "Reopen last file on launch",
        target: nil,
        action: nil
    )
    private let pinCheckbox = NSButton(
        checkboxWithTitle: "Restore float-on-top on launch",
        target: nil,
        action: nil
    )
    private let tipsOnStartupCheckbox = NSButton(
        checkboxWithTitle: "Show tip on startup",
        target: nil,
        action: nil
    )
    private let wordCompletionCheckbox = NSButton(
        checkboxWithTitle: "Word completion in Insert (buffer words)",
        target: nil,
        action: nil
    )
    private let spellCheckingCheckbox = NSButton(
        checkboxWithTitle: "Check spelling in Insert",
        target: nil,
        action: nil
    )
    private let typewriterSoundCheckbox = NSButton(
        checkboxWithTitle: "Sound effects (typing, motions, save, tasks)",
        target: nil,
        action: nil
    )
    private let debugLoggingCheckbox = NSButton(
        checkboxWithTitle: "Debug logging (vim / newlines)",
        target: nil,
        action: nil
    )
    private let revealLogButton = NSButton(title: "Reveal Log", target: nil, action: nil)
    private let lastFileLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Roobytes Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentView = buildContent()
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: 420, height: max(content.fittingSize.height, 380)))
        }
        reloadFromSettings()
    }

    private func buildContent() -> NSView {
        let root = NSView()

        let column = NSStackView()
        column.orientation = .vertical
        column.spacing = 16
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)

        // Theme
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        appearanceControl.segmentStyle = .rounded
        appearanceControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for i in 0..<appearanceControl.segmentCount {
            appearanceControl.setWidth(0, forSegment: i)
        }
        let themeBlock = section(title: "Theme", body: appearanceControl)
        column.addArrangedSubview(themeBlock)

        // Accent
        accentStack.orientation = .horizontal
        accentStack.spacing = 8
        accentStack.alignment = .centerY
        accentSwatches = AccentPreference.allCases.enumerated().map { idx, preset in
            let swatch = AccentSwatchButton(color: preset.color)
            swatch.toolTip = preset.title
            swatch.target = self
            swatch.action = #selector(accentClicked(_:))
            swatch.tag = idx
            accentStack.addArrangedSubview(swatch)
            return swatch
        }
        column.addArrangedSubview(section(
            title: "Accent",
            caption: "Caret, pin, focus, and code",
            body: accentStack
        ))

        // Startup
        reopenCheckbox.target = self
        reopenCheckbox.action = #selector(toggleReopen(_:))
        pinCheckbox.target = self
        pinCheckbox.action = #selector(togglePinRestore(_:))
        tipsOnStartupCheckbox.target = self
        tipsOnStartupCheckbox.action = #selector(toggleTipsOnStartup(_:))
        let checks = NSStackView(views: [reopenCheckbox, pinCheckbox, tipsOnStartupCheckbox])
        checks.orientation = .vertical
        checks.alignment = .leading
        checks.spacing = 6
        column.addArrangedSubview(section(title: "Startup", body: checks))

        // Editor
        wordCompletionCheckbox.target = self
        wordCompletionCheckbox.action = #selector(toggleWordCompletion(_:))
        spellCheckingCheckbox.target = self
        spellCheckingCheckbox.action = #selector(toggleSpellChecking(_:))
        let editorChecks = NSStackView(views: [wordCompletionCheckbox, spellCheckingCheckbox])
        editorChecks.orientation = .vertical
        editorChecks.alignment = .leading
        editorChecks.spacing = 6
        column.addArrangedSubview(section(
            title: "Editor",
            caption: "Word completion also supports :complete / :cmp",
            body: editorChecks
        ))

        // Sound
        typewriterSoundCheckbox.target = self
        typewriterSoundCheckbox.action = #selector(toggleTypewriterSound(_:))
        column.addArrangedSubview(section(
            title: "Sound",
            caption: "Clicks & chimes · off by default",
            body: typewriterSoundCheckbox
        ))

        // Diagnostics
        debugLoggingCheckbox.target = self
        debugLoggingCheckbox.action = #selector(toggleDebugLogging(_:))
        revealLogButton.target = self
        revealLogButton.action = #selector(revealDebugLog(_:))
        revealLogButton.bezelStyle = .rounded
        revealLogButton.controlSize = .small
        let debugRow = NSStackView(views: [debugLoggingCheckbox, revealLogButton])
        debugRow.orientation = .horizontal
        debugRow.alignment = .centerY
        debugRow.spacing = 12
        debugRow.distribution = .fill
        debugLoggingCheckbox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        column.addArrangedSubview(section(
            title: "Diagnostics",
            caption: "~/Library/Logs/Roobytes/debug.log",
            body: debugRow
        ))

        // Last file — one row: truncated path + Clear
        lastFileLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        lastFileLabel.textColor = .secondaryLabelColor
        lastFileLabel.maximumNumberOfLines = 1
        lastFileLabel.lineBreakMode = .byTruncatingMiddle
        lastFileLabel.cell?.truncatesLastVisibleLine = true
        lastFileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lastFileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        clearButton.target = self
        clearButton.action = #selector(clearLastFile(_:))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.setContentHuggingPriority(.required, for: .horizontal)

        let pathRow = NSStackView(views: [lastFileLabel, clearButton])
        pathRow.orientation = .horizontal
        pathRow.alignment = .centerY
        pathRow.spacing = 10
        pathRow.distribution = .fill
        column.addArrangedSubview(section(title: "Last opened", body: pathRow))

        let contentWidth: CGFloat = 380
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            column.widthAnchor.constraint(equalToConstant: contentWidth),
        ])

        // Force every section to the same full width (avoids NSStackView shrink-wrapping).
        for view in column.arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }

        return root
    }

    private func section(title: String, caption: String? = nil, body: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let cardBody = NSStackView()
        cardBody.orientation = .vertical
        cardBody.alignment = .leading
        cardBody.spacing = 8
        cardBody.translatesAutoresizingMaskIntoConstraints = false

        if let caption {
            let cap = NSTextField(labelWithString: caption)
            cap.font = .systemFont(ofSize: 11)
            cap.textColor = .tertiaryLabelColor
            cardBody.addArrangedSubview(cap)
        }
        body.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cardBody.addArrangedSubview(body)

        let card = PrefsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardBody)
        NSLayoutConstraint.activate([
            cardBody.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            cardBody.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            cardBody.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            cardBody.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            body.widthAnchor.constraint(equalTo: cardBody.widthAnchor),
        ])

        let stack = NSStackView(views: [titleLabel, card])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return stack
    }

    func showPreferences() {
        reloadFromSettings()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reloadFromSettings() {
        let settings = RoobytesSettings.shared
        reopenCheckbox.state = settings.reopenLastFileOnLaunch ? .on : .off
        pinCheckbox.state = settings.restorePinOnLaunch ? .on : .off
        tipsOnStartupCheckbox.state = settings.tipsOnStartup ? .on : .off
        wordCompletionCheckbox.state = settings.wordCompletion ? .on : .off
        spellCheckingCheckbox.state = settings.spellChecking ? .on : .off
        typewriterSoundCheckbox.state = settings.typewriterSound ? .on : .off
        debugLoggingCheckbox.state = settings.debugLogging ? .on : .off

        if let idx = AppearancePreference.allCases.firstIndex(of: settings.appearance) {
            appearanceControl.selectedSegment = idx
        }

        refreshAccentSelection()

        if let file = settings.lastFilePath {
            lastFileLabel.stringValue = displayPath(file)
            clearButton.isEnabled = true
        } else if let folder = settings.lastFolderPath {
            lastFileLabel.stringValue = displayPath(folder) + " · folder"
            clearButton.isEnabled = true
        } else {
            lastFileLabel.stringValue = "None yet"
            clearButton.isEnabled = false
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func refreshAccentSelection() {
        let selected = RoobytesSettings.shared.accent
        for (idx, swatch) in accentSwatches.enumerated() {
            let preset = AccentPreference.allCases[idx]
            swatch.swatchColor = preset.color
            swatch.isSelectedSwatch = preset == selected
        }
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        let modes = AppearancePreference.allCases
        guard idx >= 0, idx < modes.count else { return }
        RoobytesSettings.shared.appearance = modes[idx]
        AppDelegate.shared?.applyAppearance()
    }

    @objc private func accentClicked(_ sender: NSButton) {
        let presets = AccentPreference.allCases
        guard sender.tag >= 0, sender.tag < presets.count else { return }
        RoobytesSettings.shared.accent = presets[sender.tag]
        refreshAccentSelection()
        AppDelegate.shared?.applyAccent()
    }

    @objc private func toggleReopen(_ sender: NSButton) {
        RoobytesSettings.shared.reopenLastFileOnLaunch = sender.state == .on
    }

    @objc private func togglePinRestore(_ sender: NSButton) {
        RoobytesSettings.shared.restorePinOnLaunch = sender.state == .on
    }

    @objc private func toggleTipsOnStartup(_ sender: NSButton) {
        RoobytesSettings.shared.tipsOnStartup = sender.state == .on
    }

    @objc private func toggleWordCompletion(_ sender: NSButton) {
        RoobytesSettings.shared.wordCompletion = sender.state == .on
    }

    @objc private func toggleSpellChecking(_ sender: NSButton) {
        RoobytesSettings.shared.spellChecking = sender.state == .on
    }

    @objc private func toggleTypewriterSound(_ sender: NSButton) {
        let on = sender.state == .on
        RoobytesSettings.shared.typewriterSound = on
        if on {
            TypewriterSound.shared.playPreview()
        }
    }

    @objc private func toggleDebugLogging(_ sender: NSButton) {
        RoobytesSettings.shared.debugLogging = sender.state == .on
    }

    @objc private func revealDebugLog(_ sender: Any?) {
        let file = RoobytesDebugLog.logFileURL
        let dir = RoobytesDebugLog.logDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file.path) {
            // Touch an empty file so Finder has something to select.
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    @objc private func clearLastFile(_ sender: Any?) {
        RoobytesSettings.shared.clearLastOpened()
        reloadFromSettings()
    }
}

// MARK: - Pieces

@MainActor
private final class AccentSwatchButton: NSButton {
    var swatchColor: NSColor = .systemYellow {
        didSet { needsDisplay = true }
    }

    var isSelectedSwatch = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        swatchColor = color
        title = ""
        image = nil
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 26, height: 26) }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        swatchColor.setFill()
        fill.fill()

        if isSelectedSwatch {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 2
            swatchColor.setStroke()
            ring.stroke()
        } else if isHighlighted {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1.5
            NSColor.tertiaryLabelColor.setStroke()
            ring.stroke()
        }
    }
}

@MainActor
private final class PrefsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

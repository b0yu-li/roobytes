import AppKit

/// Compact LazyVim-style candidate menu + caret ghost for insert-mode word completion.
@MainActor
final class WordCompletionMenu: NSObject {
    private let panel = NSView()
    private let glass = NSVisualEffectView()
    private let tint = NSView()
    private let stack = NSStackView()
    private let ghostLabel = NSTextField(labelWithString: "")

    private weak var hostView: NSView?
    private var panelX: NSLayoutConstraint?
    private var panelY: NSLayoutConstraint?
    private var panelWidthConstraint: NSLayoutConstraint?
    private var panelHeightConstraint: NSLayoutConstraint?
    private var ghostX: NSLayoutConstraint?
    private var ghostY: NSLayoutConstraint?

    private var candidates: [String] = []
    private var selectedIndex: Int = 0
    private var typedPrefix: String = ""
    private var editorFont: NSFont = RoobytesFont.regular(size: 13)
    private var rowButtons: [WordCompletionRowButton] = []

    private let rowHeight: CGFloat = 22
    private let maxVisibleRows = 8
    private let minPanelWidth: CGFloat = 96
    private let maxPanelWidth: CGFloat = 260
    private let padX: CGFloat = 6
    private let padY: CGFloat = 5

    var isVisible: Bool { !(panel.isHidden) }
    var selectedCandidate: String? {
        guard selectedIndex >= 0, selectedIndex < candidates.count else { return nil }
        return candidates[selectedIndex]
    }
    var prefix: String { typedPrefix }

    override init() {
        super.init()
    }

    func install(in host: NSView) {
        hostView = host

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.wantsLayer = true
        panel.layer?.masksToBounds = false
        panel.shadow = NSShadow()
        panel.layer?.shadowOpacity = 0.20
        panel.layer?.shadowRadius = 8
        panel.layer?.shadowOffset = CGSize(width: 0, height: -1)
        panel.isHidden = true

        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.material = .popover
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 7
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true

        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: padY, left: padX, bottom: padY, right: padX)
        stack.distribution = .fill

        ghostLabel.translatesAutoresizingMaskIntoConstraints = false
        ghostLabel.isHidden = true
        ghostLabel.drawsBackground = false
        ghostLabel.isBordered = false
        ghostLabel.lineBreakMode = .byClipping
        ghostLabel.setContentHuggingPriority(.required, for: .horizontal)
        ghostLabel.cell?.setAccessibilityElement(false)

        panel.addSubview(glass)
        glass.addSubview(tint)
        glass.addSubview(stack)
        host.addSubview(panel)
        host.addSubview(ghostLabel)

        let x = panel.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 0)
        let y = panel.topAnchor.constraint(equalTo: host.topAnchor, constant: 0)
        let w = panel.widthAnchor.constraint(equalToConstant: minPanelWidth)
        let h = panel.heightAnchor.constraint(equalToConstant: rowHeight + padY * 2)
        panelX = x
        panelY = y
        panelWidthConstraint = w
        panelHeightConstraint = h

        let gx = ghostLabel.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 0)
        let gy = ghostLabel.topAnchor.constraint(equalTo: host.topAnchor, constant: 0)
        ghostX = gx
        ghostY = gy

        NSLayoutConstraint.activate([
            x, y, w, h,
            glass.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            glass.topAnchor.constraint(equalTo: panel.topAnchor),
            glass.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            tint.topAnchor.constraint(equalTo: glass.topAnchor),
            tint.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            gx, gy,
        ])

        applyChrome()
    }

    func show(
        candidates: [String],
        prefix: String,
        menuOriginInHost: NSPoint,
        ghostOriginInHost: NSPoint,
        editorFont: NSFont,
        hostBounds: CGSize,
        selected: Int = 0
    ) {
        guard !candidates.isEmpty else {
            hide()
            return
        }
        typedPrefix = prefix
        self.candidates = Array(candidates.prefix(maxVisibleRows))
        self.editorFont = editorFont
        selectedIndex = min(max(0, selected), self.candidates.count - 1)
        applyChrome()
        rebuildRows()

        let longest = self.candidates
            .map { BufferWordIndex.displayForm(candidate: $0, prefix: prefix).count }
            .max() ?? 8
        let charW = max(editorFont.maximumAdvancement.width, 7.5)
        let width = min(
            maxPanelWidth,
            max(minPanelWidth, CGFloat(longest) * charW + padX * 2 + 12)
        )
        let height = CGFloat(self.candidates.count) * rowHeight
            + CGFloat(max(0, self.candidates.count - 1)) * stack.spacing
            + padY * 2
        panelWidthConstraint?.constant = width
        panelHeightConstraint?.constant = height

        let margin: CGFloat = 8
        var menuX = menuOriginInHost.x - padX // align label text with typed prefix, not the chrome pad
        var menuY = menuOriginInHost.y
        // Shift left just enough to stay on-screen (don’t jump to the far trailing edge).
        if menuX + width > hostBounds.width - margin {
            menuX = hostBounds.width - width - margin
        }
        menuX = max(margin, menuX)
        if menuY + height > hostBounds.height - margin {
            // Flip above the caret line.
            menuY = max(margin, menuOriginInHost.y - height - 24)
        }
        menuY = max(margin, menuY)

        panelX?.constant = menuX
        panelY?.constant = menuY
        panel.isHidden = false
        hostView?.addSubview(panel, positioned: .above, relativeTo: nil)
        hostView?.addSubview(ghostLabel, positioned: .above, relativeTo: nil)
        refreshGhost(at: ghostOriginInHost)
    }

    func hide() {
        candidates = []
        typedPrefix = ""
        selectedIndex = 0
        panel.isHidden = true
        ghostLabel.isHidden = true
        ghostLabel.stringValue = ""
        clearRows()
    }

    func moveSelection(_ delta: Int) {
        guard !candidates.isEmpty else { return }
        let n = candidates.count
        selectedIndex = (selectedIndex + delta % n + n) % n
        refreshRowSelection()
        let origin = NSPoint(x: ghostX?.constant ?? 0, y: ghostY?.constant ?? 0)
        refreshGhost(at: origin)
    }

    func updateGhost(originInHost: NSPoint) {
        refreshGhost(at: originInHost)
    }

    func refreshAccent() {
        applyChrome()
        refreshRowSelection()
    }

    private func clearRows() {
        for button in rowButtons {
            stack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        rowButtons = []
    }

    private func rebuildRows() {
        clearRows()
        for (idx, word) in candidates.enumerated() {
            let button = WordCompletionRowButton(frame: .zero)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            button.target = self
            button.action = #selector(rowClicked(_:))
            button.tag = idx
            button.attributedTitle = attributedCandidate(word, selected: idx == selectedIndex)
            stack.addArrangedSubview(button)
            rowButtons.append(button)
        }
        refreshRowSelection()
    }

    private func refreshRowSelection() {
        for (idx, button) in rowButtons.enumerated() {
            let selected = idx == selectedIndex
            button.isSelectedRow = selected
            guard idx < candidates.count else { continue }
            button.attributedTitle = attributedCandidate(candidates[idx], selected: selected)
            button.needsDisplay = true
        }
    }

    @objc private func rowClicked(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < candidates.count else { return }
        selectedIndex = idx
        refreshRowSelection()
        let origin = NSPoint(x: ghostX?.constant ?? 0, y: ghostY?.constant ?? 0)
        refreshGhost(at: origin)
    }

    private func refreshGhost(at originInHost: NSPoint) {
        guard let word = selectedCandidate,
              let suffix = BufferWordIndex.ghostSuffix(candidate: word, prefix: typedPrefix),
              !suffix.isEmpty
        else {
            ghostLabel.isHidden = true
            ghostLabel.stringValue = ""
            return
        }
        ghostLabel.stringValue = suffix
        ghostLabel.font = editorFont
        ghostLabel.textColor = RoobytesTheme.editorTertiary.withAlphaComponent(0.55)
        ghostX?.constant = originInHost.x
        ghostY?.constant = originInHost.y
        ghostLabel.isHidden = false
    }

    private func applyChrome() {
        RoobytesGlassChrome.apply(
            shell: panel,
            glass: glass,
            tint: tint,
            highlight: nil,
            style: .quiet
        )
        glass.layer?.cornerRadius = 7
    }

    private func attributedCandidate(_ word: String, selected: Bool) -> NSAttributedString {
        let display = BufferWordIndex.displayForm(candidate: word, prefix: typedPrefix)
        let result = NSMutableAttributedString(string: display)
        let font = editorFont.withSize(max(12, editorFont.pointSize - 0.5))
        let full = NSRange(location: 0, length: (display as NSString).length)
        result.addAttributes([.font: font, .foregroundColor: RoobytesTheme.editorForeground], range: full)
        let prefixLen = min(typedPrefix.count, display.count)
        if prefixLen > 0 {
            result.addAttribute(
                .foregroundColor,
                value: RoobytesTheme.editorTertiary,
                range: NSRange(location: 0, length: prefixLen)
            )
        }
        if display.count > prefixLen {
            result.addAttribute(
                .foregroundColor,
                value: selected ? RoobytesAccent.bright : RoobytesTheme.editorForeground,
                range: NSRange(location: prefixLen, length: display.count - prefixLen)
            )
        }
        return result
    }
}

/// Single completion row — draws its own accent wash when selected.
private final class WordCompletionRowButton: NSButton {
    var isSelectedRow = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryChange)
        focusRingType = .none
        imagePosition = .noImage
        alignment = .left
        // Avoid AppKit’s default content padding so prefix lines up with the caret word.
        if let cell = cell as? NSButtonCell {
            cell.lineBreakMode = .byTruncatingTail
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        var size = attributedTitle.size()
        size.width += 8
        size.height = max(size.height, 18)
        return size
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedRow {
            RoobytesAccent.color.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let titleSize = attributedTitle.size()
        let x: CGFloat = 4
        let y = (bounds.height - titleSize.height) * 0.5
        attributedTitle.draw(at: NSPoint(x: x, y: y))
    }
}

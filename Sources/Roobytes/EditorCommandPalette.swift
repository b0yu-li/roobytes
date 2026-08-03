import AppKit

/// Frosted HUD shell shared by `:`, flash messages, `:h`, tips, and chord hints.
///
/// Owns the NSView tree and layout/chrome only — vim buffer / key routing stay in the editor.
@MainActor
final class EditorCommandPalette {
    enum Placement {
        case topCenter
        case center
        case bottomTrailing
    }

    enum Style {
        case quiet
        case flash
        case panel
        case help

        var glass: RoobytesGlassChrome.Style {
            switch self {
            case .quiet: return .quiet
            case .flash: return .flash
            case .panel: return .panel
            case .help: return .help
            }
        }
    }

    private let scrim = HelpScrimView()
    private let shell = NSView()
    private let glass = NSVisualEffectView()
    private let tint = NSView()
    private let highlight = RoobytesGlassChrome.makeHighlightView()
    private let contentScroll = NSScrollView()
    private let contentDocument = FlippedDocumentView()
    private let label = NSTextField(labelWithString: "")

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var centerYConstraint: NSLayoutConstraint?
    private var centerXConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var labelInsets: (leading: NSLayoutConstraint, trailing: NSLayoutConstraint, top: NSLayoutConstraint, bottom: NSLayoutConstraint)?
    private var labelCenterYConstraint: NSLayoutConstraint?
    private var labelWidthConstraint: NSLayoutConstraint?
    private var scrollInsets: (leading: NSLayoutConstraint, trailing: NSLayoutConstraint, top: NSLayoutConstraint, bottom: NSLayoutConstraint)?

    private weak var hostView: NSView?

    /// Called when the help scrim is clicked.
    var onScrimClick: (() -> Void)?

    var isHidden: Bool {
        get { shell.isHidden }
        set { shell.isHidden = newValue }
    }

    /// Confetti / celebration anchor in the host’s coordinate space.
    func anchorPoint(in hostView: NSView) -> NSPoint {
        shell.layoutSubtreeIfNeeded()
        let mid = NSPoint(x: shell.bounds.midX, y: shell.bounds.midY)
        return shell.convert(mid, to: hostView)
    }

    func install(in root: NSView, alignedTo scrollView: NSScrollView) {
        hostView = root

        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.wantsLayer = true
        scrim.isHidden = true
        scrim.alphaValue = 0
        scrim.layer?.backgroundColor = NSColor.black.cgColor
        scrim.onClick = { [weak self] in
            self?.onScrimClick?()
        }

        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.wantsLayer = true
        shell.isHidden = true
        shell.layer?.masksToBounds = false
        shell.shadow = NSShadow()
        shell.layer?.shadowOpacity = 0.38
        shell.layer?.shadowRadius = 18
        shell.layer?.shadowOffset = CGSize(width: 0, height: -3)

        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.material = .hudWindow
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.isEmphasized = true
        glass.wantsLayer = true
        glass.layer?.cornerRadius = RoobytesGlassChrome.cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true

        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.clear.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = RoobytesFont.regular(size: 15)
        label.alignment = .left
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)

        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.drawsBackground = false
        contentScroll.backgroundColor = .clear
        contentScroll.borderType = .noBorder
        contentScroll.hasVerticalScroller = false
        contentScroll.hasHorizontalScroller = false
        contentScroll.autohidesScrollers = true
        contentScroll.scrollerStyle = .overlay
        contentDocument.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.documentView = contentDocument
        contentDocument.addSubview(label)

        root.addSubview(scrim)
        shell.addSubview(glass)
        glass.addSubview(tint)
        glass.addSubview(highlight)
        glass.addSubview(contentScroll)
        root.addSubview(shell)

        let width = shell.widthAnchor.constraint(equalToConstant: 360)
        widthConstraint = width
        let height = shell.heightAnchor.constraint(equalToConstant: 40)
        heightConstraint = height

        let top = shell.topAnchor.constraint(equalTo: root.topAnchor, constant: 14)
        let centerY = shell.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -8)
        let centerX = shell.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor)
        let bottom = shell.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        let trailing = shell.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16)
        centerY.isActive = false
        bottom.isActive = false
        trailing.isActive = false
        topConstraint = top
        centerYConstraint = centerY
        centerXConstraint = centerX
        bottomConstraint = bottom
        trailingConstraint = trailing

        let scrollLeading = contentScroll.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 0)
        let scrollTrailing = contentScroll.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: 0)
        let scrollTop = contentScroll.topAnchor.constraint(equalTo: glass.topAnchor, constant: 0)
        let scrollBottom = contentScroll.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: 0)
        scrollInsets = (scrollLeading, scrollTrailing, scrollTop, scrollBottom)

        let labelLeading = label.leadingAnchor.constraint(equalTo: contentDocument.leadingAnchor, constant: 16)
        let labelTrailing = label.trailingAnchor.constraint(equalTo: contentDocument.trailingAnchor, constant: -16)
        labelTrailing.priority = .defaultHigh
        let labelTop = label.topAnchor.constraint(equalTo: contentDocument.topAnchor, constant: 10)
        let labelBottom = label.bottomAnchor.constraint(equalTo: contentDocument.bottomAnchor, constant: -10)
        labelInsets = (labelLeading, labelTrailing, labelTop, labelBottom)

        let labelWidth = label.widthAnchor.constraint(equalTo: contentDocument.widthAnchor, constant: -32)
        labelWidthConstraint = labelWidth

        let labelCenterY = label.centerYAnchor.constraint(equalTo: contentDocument.centerYAnchor, constant: 0.5)
        self.labelCenterYConstraint = labelCenterY

        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: root.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            top,
            centerX,
            width,
            height,
            shell.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -40),
            shell.heightAnchor.constraint(lessThanOrEqualTo: root.heightAnchor, constant: -40),

            glass.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            glass.topAnchor.constraint(equalTo: shell.topAnchor),
            glass.bottomAnchor.constraint(equalTo: shell.bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            tint.topAnchor.constraint(equalTo: glass.topAnchor),
            tint.bottomAnchor.constraint(equalTo: glass.bottomAnchor),

            highlight.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            highlight.topAnchor.constraint(equalTo: glass.topAnchor),
            highlight.heightAnchor.constraint(equalToConstant: RoobytesGlassChrome.highlightHeight),

            scrollLeading,
            scrollTrailing,
            scrollTop,
            scrollBottom,

            contentDocument.leadingAnchor.constraint(equalTo: contentScroll.contentView.leadingAnchor),
            contentDocument.topAnchor.constraint(equalTo: contentScroll.contentView.topAnchor),
            contentDocument.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
            contentDocument.heightAnchor.constraint(greaterThanOrEqualTo: contentScroll.contentView.heightAnchor),

            labelLeading,
            labelWidth,
            labelCenterY,
        ])

        applyChrome(style: .quiet, labelFontSize: 15, alignment: .left)
    }

    func setPlacement(_ placement: Placement) {
        switch placement {
        case .topCenter:
            centerYConstraint?.isActive = false
            bottomConstraint?.isActive = false
            trailingConstraint?.isActive = false
            topConstraint?.isActive = true
            centerXConstraint?.isActive = true
        case .center:
            topConstraint?.isActive = false
            bottomConstraint?.isActive = false
            trailingConstraint?.isActive = false
            centerYConstraint?.isActive = true
            centerXConstraint?.isActive = true
        case .bottomTrailing:
            topConstraint?.isActive = false
            centerYConstraint?.isActive = false
            centerXConstraint?.isActive = false
            bottomConstraint?.isActive = true
            trailingConstraint?.isActive = true
        }
    }

    func applyChrome(style: Style, labelFontSize: CGFloat, alignment: NSTextAlignment) {
        RoobytesGlassChrome.apply(
            shell: shell,
            glass: glass,
            tint: tint,
            highlight: highlight,
            style: style.glass
        )
        label.textColor = .labelColor
        label.font = RoobytesFont.regular(size: labelFontSize)
        label.alignment = alignment

        let inset: CGFloat = style == .help ? 20 : 16
        let vertical: CGFloat = style == .help ? 16 : 10
        labelInsets?.leading.constant = inset
        labelInsets?.trailing.constant = -inset
        labelInsets?.top.constant = vertical
        labelInsets?.bottom.constant = -vertical
        labelWidthConstraint?.constant = -(inset * 2)

        if style == .help {
            labelCenterYConstraint?.isActive = false
            labelInsets?.top.isActive = true
            labelInsets?.bottom.isActive = true
            contentScroll.hasVerticalScroller = true
            contentScroll.scrollerStyle = .overlay
        } else {
            labelInsets?.top.isActive = false
            labelInsets?.bottom.isActive = false
            labelCenterYConstraint?.isActive = true
            contentScroll.hasVerticalScroller = false
            contentScroll.contentView.scroll(to: .zero)
        }
    }

    func show(withScrim: Bool = false) {
        if withScrim {
            scrim.isHidden = false
            scrim.alphaValue = 0.32
        } else {
            hideScrim()
        }
        shell.isHidden = false
        shell.alphaValue = 1
    }

    func hide(clearText: Bool = true) {
        hideScrim()
        shell.isHidden = true
        if clearText {
            label.stringValue = ""
            label.attributedStringValue = NSAttributedString(string: "")
        }
        contentScroll.hasVerticalScroller = false
        contentScroll.contentView.scroll(to: .zero)
    }

    func hideScrim() {
        scrim.alphaValue = 0
        scrim.isHidden = true
    }

    func resetLayout() {
        setPlacement(.topCenter)
        widthConstraint?.constant = 360
        heightConstraint?.constant = 40
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingHead
        label.font = RoobytesFont.regular(size: 15)
        label.alignment = .left
        labelInsets?.leading.constant = 16
        labelInsets?.trailing.constant = -16
        labelWidthConstraint?.constant = -32
        labelInsets?.top.constant = 10
        labelInsets?.top.isActive = false
        labelInsets?.bottom.constant = -10
        labelInsets?.bottom.isActive = false
        labelCenterYConstraint?.isActive = true
        contentScroll.hasVerticalScroller = false
        contentScroll.contentView.scroll(to: .zero)
        if let cell = label.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
        }
    }

    func setAttributedText(_ attributed: NSAttributedString) {
        label.attributedStringValue = attributed
    }

    func configureSingleLine(truncatingHead: Bool) {
        label.maximumNumberOfLines = 1
        label.lineBreakMode = truncatingHead ? .byTruncatingHead : .byTruncatingTail
        contentScroll.hasVerticalScroller = false
        if let cell = label.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
        }
    }

    func configureWrapping() {
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        labelCenterYConstraint?.isActive = false
        labelInsets?.top.isActive = true
        labelInsets?.bottom.isActive = true
        if let cell = label.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.isScrollable = false
        }
    }

    func resizeForSingleLine(_ text: String) {
        let font = label.font ?? RoobytesFont.regular(size: 15)
        let textW = (text as NSString).size(withAttributes: [.font: font]).width
        let width = min(max(220, textW + 48), 520)
        widthConstraint?.constant = width
        heightConstraint?.constant = 40
        label.maximumNumberOfLines = 1
        contentScroll.hasVerticalScroller = false
    }

    func resizeForMultiline(
        _ text: String,
        fontSize: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) {
        let hostHeight = hostView?.bounds.height ?? 600
        let font = RoobytesFont.regular(size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - 48, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let width = min(max(minWidth, ceil(rect.width) + 48), maxWidth)
        let height = min(max(48, ceil(rect.height) + 28), max(120, hostHeight - 40))
        widthConstraint?.constant = width
        heightConstraint?.constant = height
        contentScroll.hasVerticalScroller = false
    }

    func resizeForHelp(_ attributed: NSAttributedString) {
        let hostHeight = hostView?.bounds.height ?? 600
        let maxWidth: CGFloat = 520
        let inset: CGFloat = 20
        let vertical: CGFloat = 16
        let contentWidth = maxWidth - (inset * 2)
        let rect = attributed.boundingRect(
            with: NSSize(width: contentWidth, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let contentHeight = ceil(rect.height)
        let width = min(max(440, ceil(rect.width) + inset * 2), maxWidth)
        // Cap the panel to the window; scroll when the Ex section would otherwise clip.
        let maxPanel = max(320, hostHeight - 64)
        let height = min(max(280, contentHeight + vertical * 2), maxPanel)
        widthConstraint?.constant = width
        heightConstraint?.constant = height
        label.preferredMaxLayoutWidth = width - inset * 2
        labelWidthConstraint?.constant = -(inset * 2)
        contentScroll.hasVerticalScroller = contentHeight + vertical * 2 > height + 1
        contentScroll.contentView.scroll(to: .zero)
    }

    /// Line scroll for the help panel (`⌃e` / `⌃y`). Positive = down.
    func scrollContentLines(_ delta: Int) {
        guard delta != 0 else { return }
        // Match editor ⌃e/⌃y feel: ~2 row heights per tick for key-repeat.
        let step: CGFloat = 18 * 2
        scrollContent(by: CGFloat(delta) * step)
    }

    /// Half-page scroll for the help panel (`⌃d` / `⌃u`). Positive = down.
    func scrollContentHalfPages(_ delta: Int) {
        guard delta != 0 else { return }
        let half = max(contentScroll.contentView.bounds.height * 0.5, 48)
        scrollContent(by: CGFloat(delta) * half)
    }

    private func scrollContent(by deltaY: CGFloat) {
        let clip = contentScroll.contentView
        let docH = contentDocument.bounds.height
        let visibleH = clip.bounds.height
        let maxY = max(0, docH - visibleH)
        guard maxY > 0.5 else { return }
        let y = min(max(0, clip.bounds.origin.y + deltaY), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        contentScroll.reflectScrolledClipView(clip)
    }
}

/// A scroll document whose origin stays at the visual top when its content grows.
@MainActor
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Clickable dim behind the help panel.
@MainActor
private final class HelpScrimView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

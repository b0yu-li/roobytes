import AppKit

/// Persistent, compact mode feedback while characterwise Visual is active.
@MainActor
final class VisualModeBadge {
    private let shell = NSView()
    private let glass = NSVisualEffectView()
    private let tint = NSView()
    private let highlight = RoobytesGlassChrome.makeHighlightView()
    private let label = NSTextField(labelWithString: "")

    func install(in root: NSView, alignedTo scrollView: NSScrollView) {
        shell.translatesAutoresizingMaskIntoConstraints = false
        shell.isHidden = true
        shell.alphaValue = 0

        glass.translatesAutoresizingMaskIntoConstraints = false
        tint.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = RoobytesFont.regular(size: 12)
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.attributedStringValue = Self.badgeText()

        root.addSubview(shell)
        shell.addSubview(glass)
        glass.addSubview(tint)
        glass.addSubview(highlight)
        glass.addSubview(label)

        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            shell.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),

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

            label.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -11),
            label.topAnchor.constraint(equalTo: glass.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: glass.bottomAnchor, constant: -7),
        ])

        applyChrome()
    }

    func show() {
        applyChrome()
        label.attributedStringValue = Self.badgeText()
        guard shell.isHidden else { return }
        shell.isHidden = false
        shell.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            shell.animator().alphaValue = 1
        }
    }

    func hide() {
        guard !shell.isHidden else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            shell.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.shell.isHidden = true
            }
        })
    }

    func refreshAppearance() {
        applyChrome()
        label.attributedStringValue = Self.badgeText()
    }

    private func applyChrome() {
        RoobytesGlassChrome.apply(
            shell: shell,
            glass: glass,
            tint: tint,
            highlight: highlight,
            style: .panel
        )
    }

    private static func badgeText() -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "VISUAL",
            attributes: [
                .font: RoobytesFont.bold(size: 12),
                .foregroundColor: RoobytesAccent.bright,
                .kern: 0.5,
            ]
        )
        result.append(
            NSAttributedString(
                string: "  ·  y yank  ·  d cut  ·  ⌘B/⌘I  ·  Esc",
                attributes: [
                    .font: RoobytesFont.regular(size: 12),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        )
        return result
    }
}

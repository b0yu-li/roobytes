import AppKit
import Darwin

/// Process-wide physical-footprint sampler (3 s). Shared by all windows.
/// Matches Activity Monitor’s Memory column (`phys_footprint`), not classic RSS.
@MainActor
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    static let sampleLimit = 60
    static let didUpdateNotification = Notification.Name("Roobytes.MemoryMonitor.didUpdate")

    private(set) var samples: [Double] = []
    private(set) var currentMegabytes: Double = 0
    private(set) var peakMegabytes: Double = 0
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        sample()
        // 3 s is enough for the titlebar Mem readout; 1 Hz was pure churn.
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let mb = Self.footprintMegabytes()
        currentMegabytes = mb
        peakMegabytes = max(peakMegabytes, mb)
        samples.append(mb)
        if samples.count > Self.sampleLimit {
            samples.removeFirst(samples.count - Self.sampleLimit)
        }
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
    }

    /// Same metric as Activity Monitor → Memory (`TASK_VM_INFO.phys_footprint`).
    static func footprintMegabytes() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

@MainActor
final class MemoryStatusBarView: NSView {
    private let memLabel = NSTextField(labelWithString: "Mem —")
    private let peakLabel = NSTextField(labelWithString: "peak —")
    private let sparkline = SparklineView()
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        memLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        memLabel.textColor = .labelColor
        memLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        peakLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        peakLabel.textColor = .secondaryLabelColor
        peakLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        sparkline.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [memLabel, sparkline, peakLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sparkline.widthAnchor.constraint(equalToConstant: 120),
            sparkline.heightAnchor.constraint(equalToConstant: 16),
        ])

        observer = NotificationCenter.default.addObserver(
            forName: MemoryMonitor.didUpdateNotification,
            object: MemoryMonitor.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refresh() {
        let monitor = MemoryMonitor.shared
        memLabel.stringValue = String(format: "Mem %.0f MB", monitor.currentMegabytes)
        memLabel.toolTip = String(
            format: "Physical footprint %.0f MB (Activity Monitor) · peak %.0f MB",
            monitor.currentMegabytes,
            monitor.peakMegabytes
        )
        peakLabel.stringValue = String(format: "peak %.0f MB", monitor.peakMegabytes)
        sparkline.values = monitor.samples
        sparkline.needsDisplay = true
    }
}

@MainActor
final class SparklineView: NSView {
    var values: [Double] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count >= 2 else { return }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 1)
        let drawBounds = bounds.insetBy(dx: 1, dy: 2)
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        for (index, value) in values.enumerated() {
            let x = drawBounds.minX + drawBounds.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = drawBounds.maxY - drawBounds.height * CGFloat((value - minV) / range)
            let point = NSPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}

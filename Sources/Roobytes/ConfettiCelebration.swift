import AppKit
import QuartzCore

/// Short confetti burst when a task flips to done or `:w` writes.
@MainActor
enum ConfettiCelebration {
    private static let colors: [NSColor] = [
        RoobytesAccent.bright,
        RoobytesAccent.color,
        NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.78, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.65, alpha: 1),
    ]

    private static weak var activeEmitter: CAEmitterLayer?
    private static var particleTemplate: CGImage?

    /// Burst confetti from a point in the host view’s bounds (view coordinates).
    /// Cancels any in-flight burst first.
    static func burst(in host: NSView, at point: NSPoint) {
        host.wantsLayer = true
        guard let hostLayer = host.layer else { return }

        activeEmitter?.removeFromSuperlayer()
        activeEmitter = nil

        // NSView.layer matches the view’s flippedness — use view coords directly.
        // (Previously non-flipped hosts used `height - y`, which mirrored the burst
        // below the intended spot.)
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: point.x, y: point.y)
        emitter.emitterSize = CGSize(width: 28, height: 10)
        emitter.emitterShape = .line
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1
        emitter.zPosition = 1000

        // Screen-up depends on whether +Y is down (flipped) or up.
        let shootUp: CGFloat = host.isFlipped ? .pi * 1.5 : .pi / 2
        let gravity: CGFloat = host.isFlipped ? 420 : -420

        let particle = sharedParticleImage()
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 24
            cell.lifetime = 1.2
            cell.lifetimeRange = 0.2
            cell.velocity = 190
            cell.velocityRange = 60
            cell.emissionLongitude = shootUp
            cell.emissionRange = .pi / 2.4
            cell.spin = 5
            cell.spinRange = 8
            cell.scale = 0.7
            cell.scaleRange = 0.25
            cell.scaleSpeed = -0.3
            cell.yAcceleration = gravity
            cell.alphaSpeed = -0.6
            cell.color = color.cgColor
            cell.contents = particle
            return cell
        }

        hostLayer.addSublayer(emitter)
        activeEmitter = emitter

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if activeEmitter === emitter {
                activeEmitter = nil
            }
            emitter.removeFromSuperlayer()
        }
    }

    private static func sharedParticleImage() -> CGImage? {
        // Invalidate tiny old template if present from earlier builds in-process.
        if let particleTemplate, particleTemplate.width >= 14 {
            return particleTemplate
        }
        let size = NSSize(width: 14, height: 9)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 2,
                yRadius: 2
            )
            NSColor.white.setFill()
            path.fill()
            return true
        }
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        particleTemplate = cg
        return cg
    }
}

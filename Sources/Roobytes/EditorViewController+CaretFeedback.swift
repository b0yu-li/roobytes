import AppKit
import QuartzCore

@MainActor
extension EditorViewController {
    /// Faint block at the previous caret — answers “where was I”. Replaces any in-flight ghost.
    func playCaretOriginGhost(at rect: NSRect) {
        textView.wantsLayer = true
        clearCaretGhost()

        let layer = CALayer()
        layer.backgroundColor = RoobytesAccent.caret.cgColor
        layer.cornerRadius = 1
        layer.frame = rect
        layer.opacity = 0.40
        textView.layer?.addSublayer(layer)
        caretGhostLayer = layer

        caretFeedbackGeneration &+= 1
        let generation = caretFeedbackGeneration

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.22)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            layer?.removeFromSuperlayer()
            guard let self, let layer else { return }
            if self.caretGhostLayer === layer, self.caretFeedbackGeneration == generation {
                self.caretGhostLayer = nil
            }
        }
        layer.opacity = 0
        CATransaction.commit()
    }

    /// Brief brighten at the new caret — answers “where am I” on line jumps.
    func playCaretDestinationPulse(at rect: NSRect) {
        textView.wantsLayer = true
        clearCaretPulse()

        let expanded = rect.insetBy(dx: -1.5, dy: -1)
        let layer = CALayer()
        layer.backgroundColor = RoobytesAccent.caret.cgColor
        layer.cornerRadius = 1
        layer.frame = expanded
        layer.opacity = 0.50
        textView.layer?.addSublayer(layer)
        caretPulseLayer = layer

        let generation = caretFeedbackGeneration

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            layer?.removeFromSuperlayer()
            guard let self, let layer else { return }
            if self.caretPulseLayer === layer, self.caretFeedbackGeneration == generation {
                self.caretPulseLayer = nil
            }
        }
        layer.opacity = 0
        layer.frame = rect
        CATransaction.commit()
    }

    func clearCaretGhost() {
        caretGhostLayer?.removeFromSuperlayer()
        caretGhostLayer = nil
    }

    func clearCaretPulse() {
        caretPulseLayer?.removeFromSuperlayer()
        caretPulseLayer = nil
    }

    func clearCaretFeedback() {
        caretFeedbackGeneration &+= 1
        clearCaretGhost()
        clearCaretPulse()
    }
}

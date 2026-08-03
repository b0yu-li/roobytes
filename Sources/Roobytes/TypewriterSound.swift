import AppKit
import AVFoundation
import Foundation

/// Soft UI / typing sounds. Samples are synthesized in-memory (no bundled audio)
/// and played through `AVAudioEngine` so rapid events can overlap.
@MainActor
final class TypewriterSound {
    static let shared = TypewriterSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var keyBuffers: [AVAudioPCMBuffer] = []
    private var spaceBuffer: AVAudioPCMBuffer?
    private var returnBuffer: AVAudioPCMBuffer?
    private var deleteBuffer: AVAudioPCMBuffer?
    private var motionBuffers: [AVAudioPCMBuffer] = []
    private var writeBuffer: AVAudioPCMBuffer?
    private var taskDoneBuffers: [AVAudioPCMBuffer] = []
    private var isReady = false

    private init() {}

    private var enabled: Bool { RoobytesSettings.shared.typewriterSound }

    /// Fire a click for an inserted string (first character decides the sample family).
    func playInsert(_ text: String) {
        guard enabled, !text.isEmpty, let ch = text.first else { return }
        prepareIfNeeded()
        if ch == "\n" || ch == "\r" {
            play(returnBuffer)
        } else if ch == " " || ch == "\t" {
            play(spaceBuffer)
        } else {
            play(keyBuffers.randomElement())
        }
    }

    func playDelete() {
        guard enabled else { return }
        prepareIfNeeded()
        play(deleteBuffer)
    }

    /// Quiet tick for Normal motions / scrolls (subtler than typing).
    func playMotion() {
        guard enabled else { return }
        prepareIfNeeded()
        play(motionBuffers.randomElement())
    }

    /// Confirmation for `:w` / save.
    func playWrite() {
        guard enabled else { return }
        prepareIfNeeded()
        play(writeBuffer)
    }

    /// Celebration when a task becomes done (`md` / `⌘↩` cycle to `[x]`).
    func playTaskDone() {
        guard enabled else { return }
        prepareIfNeeded()
        // Soft rising chime — schedule notes slightly apart.
        for (i, buffer) in taskDoneBuffers.enumerated() {
            let delay = Double(i) * 0.055
            if delay == 0 {
                play(buffer)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.play(buffer)
                }
            }
        }
    }

    /// One-shot used when enabling the preference.
    func playPreview() {
        prepareIfNeeded()
        play(keyBuffers.randomElement())
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer, isReady else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func prepareIfNeeded() {
        guard !isReady else { return }

        let sampleRate: Double = 22_050
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55

        keyBuffers = [
            Self.clickBuffer(format: format, frequency: 1680, lengthMs: 14, gain: 0.28, grit: 0.35),
            Self.clickBuffer(format: format, frequency: 1520, lengthMs: 12, gain: 0.26, grit: 0.40),
            Self.clickBuffer(format: format, frequency: 1840, lengthMs: 13, gain: 0.27, grit: 0.30),
            Self.clickBuffer(format: format, frequency: 1410, lengthMs: 15, gain: 0.25, grit: 0.45),
        ]
        spaceBuffer = Self.clickBuffer(format: format, frequency: 980, lengthMs: 18, gain: 0.22, grit: 0.55)
        returnBuffer = Self.thockBuffer(format: format, frequency: 420, lengthMs: 45, gain: 0.32)
        deleteBuffer = Self.clickBuffer(format: format, frequency: 720, lengthMs: 20, gain: 0.24, grit: 0.50)

        // Softer / shorter / quieter than typing clicks.
        motionBuffers = [
            Self.clickBuffer(format: format, frequency: 2100, lengthMs: 8, gain: 0.10, grit: 0.15),
            Self.clickBuffer(format: format, frequency: 1950, lengthMs: 7, gain: 0.09, grit: 0.12),
            Self.clickBuffer(format: format, frequency: 2250, lengthMs: 8, gain: 0.09, grit: 0.18),
        ]

        writeBuffer = Self.chimeBuffer(
            format: format,
            frequencies: [523.25, 659.25], // C5 · E5
            lengthMs: 160,
            gain: 0.22
        )

        taskDoneBuffers = [
            Self.chimeBuffer(format: format, frequencies: [523.25], lengthMs: 90, gain: 0.20), // C5
            Self.chimeBuffer(format: format, frequencies: [659.25], lengthMs: 90, gain: 0.22), // E5
            Self.chimeBuffer(format: format, frequencies: [783.99], lengthMs: 140, gain: 0.24), // G5
        ]

        do {
            try engine.start()
            isReady = true
        } catch {
            isReady = false
        }
    }

    /// Short high click with a bit of grit (key press).
    private static func clickBuffer(
        format: AVAudioFormat,
        frequency: Double,
        lengthMs: Int,
        gain: Float,
        grit: Float
    ) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(Double(lengthMs) / 1000.0 * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        var seed: UInt64 = UInt64(frequency * 1000)
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let env = Float(exp(-t * 180))
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let n = Float(Int64(seed % 10_000) - 5_000) / 5_000
            let tone = Float(sin(2 * Double.pi * frequency * t))
            data[i] = (tone * (1 - grit) + n * grit) * env * gain
        }
        return buffer
    }

    /// Lower, longer thock (Return).
    private static func thockBuffer(
        format: AVAudioFormat,
        frequency: Double,
        lengthMs: Int,
        gain: Float
    ) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(Double(lengthMs) / 1000.0 * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let env = Float(exp(-t * 55))
            let tone = Float(
                sin(2 * Double.pi * frequency * t) * 0.7
                    + sin(2 * Double.pi * frequency * 2.1 * t) * 0.3
            )
            data[i] = tone * env * gain
        }
        return buffer
    }

    /// Soft multi-partial chime (save / task done).
    private static func chimeBuffer(
        format: AVAudioFormat,
        frequencies: [Double],
        lengthMs: Int,
        gain: Float
    ) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(Double(lengthMs) / 1000.0 * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        guard let data = buffer.floatChannelData?[0], !frequencies.isEmpty else { return buffer }

        let weight = 1.0 / Double(frequencies.count)
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let env = Float(exp(-t * 18)) * (1 - Float(i) / Float(max(frames, 1)) * 0.15)
            var sample: Double = 0
            for (idx, hz) in frequencies.enumerated() {
                let partial = Double(idx + 1)
                sample += sin(2 * Double.pi * hz * t) * weight * (1.0 / partial)
            }
            data[i] = Float(sample) * env * gain
        }
        return buffer
    }
}

//
//  RenderSound.swift
//  ghostWriter
//
//  The theremin wobble that plays when markdown is rendered.
//
//  An earlier version of this produced static, for three reasons worth
//  recording so they are not repeated: the buffer was scheduled with
//  `.interrupts` which cut a playing tone off mid-cycle at a non-zero sample;
//  the amplitude envelope started and ended at non-zero values, so every tone
//  began and ended with a click; and the engine was torn down while a buffer
//  was still playing, which produced a burst of noise on leaving the editor.
//
//  This version builds one continuous buffer with a smooth envelope that starts
//  and ends at exact silence, never interrupts a playing tone, and lets the
//  engine idle rather than being stopped mid-sound.
//

import AVFoundation
import Foundation

@MainActor
final class RenderSound {
    static let shared = RenderSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var isConfigured = false
    private var isPlaying = false

    private init() {}

    /// Plays one render tone. Does nothing if a tone is already sounding, so
    /// repeated taps cannot layer or clip each other.
    func play() {
        guard !isPlaying else { return }

        do {
            try configureIfNeeded()
            guard let buffer = makeToneBuffer() else { return }

            isPlaying = true
            // No `.interrupts`. Cutting a waveform off mid-cycle is what
            // produces a click, and repeated clicks are the static.
            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor in self?.isPlaying = false }
            }

            if !player.isPlaying { player.play() }
        } catch {
            isPlaying = false
        }
    }

    /// Called when leaving the editor. The engine is paused rather than stopped
    /// so nothing is torn down underneath a sounding buffer.
    func stop() {
        guard isConfigured else { return }
        player.stop()
        engine.pause()
        isPlaying = false
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            if !engine.isRunning { try engine.start() }
            return
        }

        // `.ambient` obeys the physical silent switch and mixes with other
        // audio rather than interrupting it.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: [])

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw SoundError.formatUnavailable
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()

        isConfigured = true
    }

    /// Synthesises the tone. Frequency glides smoothly between waypoints and the
    /// envelope starts and ends at exact zero, so there is no discontinuity at
    /// either edge.
    private func makeToneBuffer() -> AVAudioPCMBuffer? {
        let duration = Double.random(in: 0.85...1.25)
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = frameCount

        // Pitch waypoints, in the spirit of the web app's four ramps but kept
        // in a narrower band so the glide stays smooth at this sample rate.
        let waypoints = [
            Double.random(in: 240...380),
            Double.random(in: 300...520),
            Double.random(in: 220...400),
            Double.random(in: 320...560),
            Double.random(in: 260...440)
        ]

        let vibratoRate = Double.random(in: 4.5...7.5)
        let vibratoDepth = Double.random(in: 8...18)
        let peakAmplitude = Float.random(in: 0.10...0.16)

        var phase = 0.0
        var vibratoPhase = 0.0
        let total = Double(frameCount)

        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / total

            // Smoothly interpolate across the waypoints using a cosine ease,
            // which has no corner at the segment boundaries — a linear ramp
            // would put a kink in the pitch curve and you would hear it.
            let scaled = progress * Double(waypoints.count - 1)
            let index = min(Int(scaled), waypoints.count - 2)
            let t = scaled - Double(index)
            let eased = (1 - cos(t * .pi)) / 2
            let frequency = waypoints[index] * (1 - eased) + waypoints[index + 1] * eased

            let vibrato = sin(vibratoPhase) * vibratoDepth
            let instantaneous = max(60, frequency + vibrato)

            // A raised-cosine window over the whole tone. This is exactly zero
            // at both ends, which is what removes the click.
            let window = Float(0.5 - 0.5 * cos(2 * .pi * progress))
            // Shape it so the tone swells quickly and tails off, while still
            // reaching silence at both edges.
            let envelope = peakAmplitude * window * Float(1.0 - progress * 0.35)

            channel[frame] = Float(sin(phase)) * envelope

            phase += 2 * .pi * instantaneous / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }
            vibratoPhase += 2 * .pi * vibratoRate / sampleRate
            if vibratoPhase > 2 * .pi { vibratoPhase -= 2 * .pi }
        }

        return buffer
    }

    private enum SoundError: Error {
        case formatUnavailable
    }
}

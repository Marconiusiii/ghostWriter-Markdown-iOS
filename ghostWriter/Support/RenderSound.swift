//
//  RenderSound.swift
//  ghostWriter
//
//  The theremin wobble that plays when markdown is rendered. Ported from the
//  web app's Web Audio oscillator: a sine tone whose pitch ramps through four
//  randomised waypoints, modulated by a second oscillator acting as vibrato,
//  inside a short envelope. Every render sounds slightly different.
//
//  The audio session is configured as ambient, so the sound respects the
//  physical silent switch and never interrupts music the user is playing.
//

import AVFoundation
import Foundation

@MainActor
final class RenderSound {
    static let shared = RenderSound()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let sampleRate: Double = 44_100

    private init() {}

    /// Plays one render tone. Silently does nothing if audio is unavailable —
    /// a missing sound effect must never interfere with writing.
    func play() {
        do {
            try configureSession()
            let engine = try activeEngine()
            guard let player else { return }

            let buffer = try makeToneBuffer()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)

            if !engine.isRunning {
                try engine.start()
            }
            player.play()
        } catch {
            // Deliberately ignored. The tone is decoration.
        }
    }

    /// Releases the audio engine. Called when leaving the editor so the app is
    /// not holding audio resources while idle.
    func stop() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.ambient` is the category for non-essential sound: it obeys the
        // silent switch and mixes with other audio rather than stopping it.
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }

    private func activeEngine() throws -> AVAudioEngine {
        if let engine, player != nil { return engine }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw SoundError.formatUnavailable
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()

        self.engine = engine
        self.player = player
        return engine
    }

    /// Synthesises the tone into a buffer. The ranges here are taken from the
    /// non-spooky branch of the web app's `playRenderSound`.
    private func makeToneBuffer() throws -> AVAudioPCMBuffer {
        let duration = Double.random(in: 0.78...1.16)
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            throw SoundError.formatUnavailable
        }
        buffer.frameLength = frameCount

        // Pitch waypoints, matching the web app's four exponential ramps.
        let base = Double.random(in: 210...530)
        let wobbleOne = Double.random(in: 260...680)
        let wobbleTwo = Double.random(in: 180...440)
        let wobbleThree = Double.random(in: 220...580)
        let finalLift = Double.random(in: 290...570)

        let vibratoRate = Double.random(in: 5.2...10.0)
        let vibratoDepth = Double.random(in: 18...44)

        let attackLevel = Float.random(in: 0.034...0.074)
        let decayLevel = Float.random(in: 0.014...0.032)

        // Ramp boundaries as fractions of the total duration.
        let stops: [(Double, Double)] = [
            (0.00, base),
            (0.22, wobbleOne),
            (0.52, wobbleTwo),
            (0.78, wobbleThree),
            (0.92, finalLift),
            (1.00, finalLift)
        ]

        var phase = 0.0
        var vibratoPhase = 0.0

        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(frameCount)

            // Exponential interpolation between the surrounding waypoints,
            // which is what gives the swooping theremin character rather than
            // a flat glide.
            var frequency = finalLift
            for index in 0..<(stops.count - 1) {
                let (startAt, startValue) = stops[index]
                let (endAt, endValue) = stops[index + 1]
                if progress >= startAt && progress <= endAt {
                    let span = max(endAt - startAt, 0.0001)
                    let t = (progress - startAt) / span
                    frequency = startValue * pow(endValue / startValue, t)
                    break
                }
            }

            let vibrato = sin(vibratoPhase) * vibratoDepth
            let instantaneous = max(80, frequency + vibrato)

            // Amplitude envelope: quick attack, long decay, fade to silence.
            let amplitude: Float
            if progress < 0.07 {
                amplitude = attackLevel * Float(progress / 0.07)
            } else if progress < 0.6 {
                let t = Float((progress - 0.07) / 0.53)
                amplitude = attackLevel + (decayLevel - attackLevel) * t
            } else {
                let t = Float((progress - 0.6) / 0.4)
                amplitude = decayLevel * (1 - t)
            }

            channel[frame] = Float(sin(phase)) * amplitude

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

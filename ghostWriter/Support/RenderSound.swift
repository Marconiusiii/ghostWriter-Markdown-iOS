//
//  RenderSound.swift
//  ghostWriter
//
//  The theremin wobble that plays when markdown is rendered.
//
//  This deliberately does NOT use AVAudioEngine. Two earlier attempts did, and
//  both produced a burst of static at the moment of playback: starting an audio
//  engine and activating the audio session are not instantaneous, and doing
//  either while a buffer is being scheduled makes the output graph produce
//  garbage for the first few milliseconds.
//
//  Instead the tone is synthesised once into an in-memory WAV, and played with
//  AVAudioPlayer. There is no live audio graph to glitch, the player is fully
//  prepared before anything is heard, and the audio session is activated at
//  startup rather than at the moment of the tap.
//

import AVFoundation
import Foundation

@MainActor
final class RenderSound {
    static let shared = RenderSound()

    private var players: [AVAudioPlayer] = []
    private var sessionReady = false
    private let sampleRate: Double = 44_100

    private init() {}

    /// Prepares the audio session ahead of first use. Called when the editor
    /// appears, so the cost is paid before the user ever taps Render.
    func prepare() {
        guard !sessionReady else { return }
        do {
            // `.ambient` obeys the physical silent switch and mixes with other
            // audio rather than interrupting it.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            sessionReady = true
        } catch {
            sessionReady = false
        }
    }

    /// Plays one render tone.
    func play() {
        prepare()

        guard let data = makeWAVData(),
              let player = try? AVAudioPlayer(data: data) else { return }

        player.volume = 0.7
        // `prepareToPlay` loads buffers and readies the hardware. Skipping it is
        // what leaves the first milliseconds of output undefined.
        guard player.prepareToPlay() else { return }

        // Held until playback finishes; an AVAudioPlayer that goes out of scope
        // stops mid-sound, which is itself an audible cut.
        players.append(player)
        player.play()

        let duration = player.duration + 0.2
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.players.removeAll { !$0.isPlaying }
        }
    }

    /// Called when leaving the editor.
    func stop() {
        // Fade rather than cut, so stopping never produces a click of its own.
        for player in players where player.isPlaying {
            player.setVolume(0, fadeDuration: 0.08)
        }
        let finishing = players
        players.removeAll()
        Task {
            try? await Task.sleep(for: .seconds(0.15))
            finishing.forEach { $0.stop() }
        }
    }

    // MARK: - Synthesis

    /// Renders the tone to a complete WAV in memory.
    private func makeWAVData() -> Data? {
        let duration = Double.random(in: 0.85...1.25)
        let frameCount = Int(duration * sampleRate)
        guard frameCount > 0 else { return nil }

        // Pitch waypoints, in the spirit of the web app's four ramps.
        let waypoints = [
            Double.random(in: 240...380),
            Double.random(in: 300...520),
            Double.random(in: 220...400),
            Double.random(in: 320...560),
            Double.random(in: 260...440)
        ]

        let vibratoRate = Double.random(in: 4.5...7.5)
        let vibratoDepth = Double.random(in: 8...18)
        let peak = 0.28

        var samples = [Int16]()
        samples.reserveCapacity(frameCount)

        var phase = 0.0
        var vibratoPhase = 0.0
        let total = Double(frameCount)

        for frame in 0..<frameCount {
            let progress = Double(frame) / total

            // Cosine ease between waypoints. A linear ramp would put a corner in
            // the pitch curve, and a corner is audible.
            let scaled = progress * Double(waypoints.count - 1)
            let index = min(Int(scaled), waypoints.count - 2)
            let t = scaled - Double(index)
            let eased = (1 - cos(t * .pi)) / 2
            let frequency = waypoints[index] * (1 - eased) + waypoints[index + 1] * eased

            let vibrato = sin(vibratoPhase) * vibratoDepth
            let instantaneous = max(60, frequency + vibrato)

            // Raised-cosine window: exactly zero at both ends, so the waveform
            // begins and ends at silence with no step discontinuity.
            let window = 0.5 - 0.5 * cos(2 * .pi * progress)
            let amplitude = peak * window * (1 - progress * 0.3)

            let value = sin(phase) * amplitude
            samples.append(Int16(max(-1, min(1, value)) * 32_000))

            phase += 2 * .pi * instantaneous / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }
            vibratoPhase += 2 * .pi * vibratoRate / sampleRate
            if vibratoPhase > 2 * .pi { vibratoPhase -= 2 * .pi }
        }

        return wavData(from: samples)
    }

    /// Wraps 16-bit mono samples in a minimal WAV container.
    private func wavData(from samples: [Int16]) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)

        var data = Data()

        func append(_ string: String) {
            data.append(contentsOf: Array(string.utf8))
        }
        func append32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")

        append("fmt ")
        append32(16)
        append16(1)                      // PCM
        append16(channels)
        append32(UInt32(sampleRate))
        append32(byteRate)
        append16(blockAlign)
        append16(bitsPerSample)

        append("data")
        append32(dataSize)
        for sample in samples {
            withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
        }

        return data
    }
}

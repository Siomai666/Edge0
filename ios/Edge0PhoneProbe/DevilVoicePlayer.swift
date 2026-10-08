@preconcurrency import AVFoundation
import Foundation
import LucyCore

/// Renders speech with `AVSpeechSynthesizer.write` and plays it through pitch, distortion and
/// reverb for Lucy's voice styles. Utterances play one at a time; all state lives on `queue`.
final class DevilVoicePlayer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "lucy.devil-voice")
    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let distortion = AVAudioUnitDistortion()
    private let reverb = AVAudioUnitReverb()
    private let onIdle: @Sendable () -> Void

    private var pending: [AVSpeechUtterance] = []
    private var current: AVSpeechUtterance?
    private var connectedFormat: AVAudioFormat?
    private var scheduledBuffers = 0
    private var generation = 0

    init(onIdle: @escaping @Sendable () -> Void) {
        self.onIdle = onIdle
        super.init()
        synth.delegate = self
        let nodes: [AVAudioNode] = [player, pitch, distortion, reverb]
        nodes.forEach { engine.attach($0) }
        distortion.loadFactoryPreset(.multiDistortedSquared)
        reverb.loadFactoryPreset(.largeChamber)
    }

    func speak(_ utterance: AVSpeechUtterance, effect p: VoiceEffectParameters) {
        queue.async {
            self.pitch.pitch = p.pitchCents
            self.distortion.wetDryMix = p.distortionWetDryMix
            self.reverb.wetDryMix = p.reverbWetDryMix
            self.pending.append(utterance)
            self.writeNextIfIdle()
        }
    }

    func stop() {
        queue.async {
            self.generation += 1
            self.pending.removeAll()
            self.current = nil
            self.scheduledBuffers = 0
            self.synth.stopSpeaking(at: .immediate)
            self.player.stop()
            self.engine.stop()
        }
    }

    private func writeNextIfIdle() {
        guard current == nil, !pending.isEmpty else { return }
        let utterance = pending.removeFirst()
        current = utterance
        let gen = generation
        synth.write(utterance) { [weak self] buffer in
            let pcm = buffer as? AVAudioPCMBuffer
            self?.queue.async { self?.receive(pcm, for: utterance, generation: gen) }
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer?, for utterance: AVSpeechUtterance, generation gen: Int) {
        guard gen == generation else { return }
        guard let buffer, buffer.frameLength > 0 else {
            finish(utterance)   // a zero-length buffer marks the end of an utterance
            return
        }
        guard let floatBuffer = Self.floatBuffer(from: buffer),
              startEngine(format: floatBuffer.format) else { return }
        scheduledBuffers += 1
        player.scheduleBuffer(floatBuffer) { [weak self] in
            self?.queue.async { self?.bufferPlayed(generation: gen) }
        }
        if !player.isPlaying { player.play() }
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        guard current === utterance else { return }
        current = nil
        writeNextIfIdle()
        notifyIfIdle()
    }

    private func bufferPlayed(generation gen: Int) {
        guard gen == generation else { return }
        scheduledBuffers = max(0, scheduledBuffers - 1)
        notifyIfIdle()
    }

    private func notifyIfIdle() {
        if scheduledBuffers == 0, current == nil, pending.isEmpty { onIdle() }
    }

    private func startEngine(format: AVAudioFormat) -> Bool {
        if connectedFormat != format {
            player.stop()
            engine.stop()
            engine.connect(player, to: pitch, format: format)
            engine.connect(pitch, to: distortion, format: format)
            engine.connect(distortion, to: reverb, format: format)
            engine.connect(reverb, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        guard !engine.isRunning else { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private static func floatBuffer(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format.commonFormat == .pcmFormatFloat32 { return buffer }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: buffer.format.sampleRate,
                                         channels: buffer.format.channelCount,
                                         interleaved: false),
              let converter = AVAudioConverter(from: buffer.format, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: buffer.frameLength)
        else { return nil }
        do {
            try converter.convert(to: out, from: buffer)
        } catch {
            return nil
        }
        return out
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queue.async { self.finish(utterance) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queue.async { self.finish(utterance) }
    }
}

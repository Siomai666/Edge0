@preconcurrency import AVFoundation
import Foundation
import LucyCore

/// Speaks Lucy's replies sentence by sentence, with the optional devil effect.
@MainActor
final class VoiceOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synth = AVSpeechSynthesizer()
    private var chunker = SpeechChunker()
    private var replyFinished = false
    private lazy var devil = DevilVoicePlayer { [weak self] in
        Task { @MainActor in self?.isSpeaking = false }
    }

    override init() {
        super.init()
        synth.delegate = self
    }

    func beginReply() {
        stop()
        chunker = SpeechChunker()
        replyFinished = false
    }

    /// `fullText` is the whole reply so far; only newly completed sentences are spoken.
    func feed(_ fullText: String, final: Bool) {
        guard AssistantPrefs.speakReplies, !replyFinished else { return }
        if final { replyFinished = true }
        for sentence in chunker.take(from: fullText, final: final) { speak(sentence) }
    }

    func speak(_ text: String) {
        let cleaned = SpeechText.clean(text)
        guard !cleaned.isEmpty else { return }
        AudioSession.activateForPlayback()
        let preset = AssistantPrefs.persona.preset
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AssistantPrefs.voiceID.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.pitchMultiplier = preset.pitch
        utterance.rate = preset.rate
        isSpeaking = true
        let strength = AssistantPrefs.devilEffect
        if DevilEffect.isActive(strength: strength) {
            devil.speak(utterance, strength: strength)
        } else {
            synth.speak(utterance)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        devil.stop()
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = self.synth.isSpeaking }
    }
}

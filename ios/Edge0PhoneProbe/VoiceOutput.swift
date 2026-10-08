@preconcurrency import AVFoundation
import Foundation
import LucyCore

/// Speaks Lucy's replies sentence by sentence in the chosen voice style.
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
        let style = AssistantPrefs.voiceStyle
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = Self.voice(for: style)
        utterance.pitchMultiplier = style.pitch
        utterance.rate = style.rate
        isSpeaking = true
        let effect = style.effect(strength: AssistantPrefs.effectStrength)
        if effect.isAudible {
            devil.speak(utterance, effect: effect)
        } else {
            synth.speak(utterance)
        }
    }

    /// The user's chosen voice, else the best installed voice for the style.
    static func voice(for style: VoiceStyle) -> AVSpeechSynthesisVoice? {
        if let id = AssistantPrefs.voiceID, let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let candidates = installed.map {
            VoiceCandidate(id: $0.identifier, language: $0.language, isFemale: $0.gender == .female,
                           quality: $0.quality.rawValue,
                           isPersonal: $0.voiceTraits.contains(.isPersonalVoice))
        }
        if let id = VoicePicker.pick(from: candidates, style: style) {
            return AVSpeechSynthesisVoice(identifier: id)
        }
        return AVSpeechSynthesisVoice(language: style.preferredLanguage)
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

import Foundation

/// Audio processing applied on top of an Apple voice.
public struct VoiceEffectParameters: Equatable, Sendable {
    /// AVAudioUnitTimePitch.pitch, in cents (negative = deeper).
    public let pitchCents: Float
    /// AVAudioUnitDistortion.wetDryMix, 0–100.
    public let distortionWetDryMix: Float
    /// AVAudioUnitReverb.wetDryMix, 0–100.
    public let reverbWetDryMix: Float

    public static let none = VoiceEffectParameters(pitchCents: 0, distortionWetDryMix: 0, reverbWetDryMix: 0)

    /// False when the effect would be inaudible, so plain system speech can be used.
    public var isAudible: Bool {
        abs(pitchCents) > 1 || distortionWetDryMix > 0.1 || reverbWetDryMix > 0.1
    }
}

/// How Lucy sounds: which kind of Apple voice to prefer, delivery, and audio effect.
public enum VoiceStyle: String, CaseIterable, Codable, Sendable {
    case villainQueen, demon, plain

    public static let defaultStyle = VoiceStyle.villainQueen
    public static let defaultStrength = 1.0

    public var title: String {
        switch self {
        case .villainQueen: "Cold villain queen"
        case .demon: "Demon"
        case .plain: "Plain"
        }
    }

    /// BCP-47 language of the voice to auto-pick when the user hasn't chosen one.
    public var preferredLanguage: String {
        switch self {
        case .villainQueen: "en-GB"
        case .demon, .plain: "en-US"
        }
    }

    /// AVSpeechUtterance pitchMultiplier (0.5–2.0).
    public var pitch: Float {
        switch self {
        case .villainQueen: 0.92
        case .demon: 0.85
        case .plain: 1.0
        }
    }

    /// AVSpeechUtterance rate (0–1; system default 0.5).
    public var rate: Float {
        switch self {
        case .villainQueen: 0.42
        case .demon: 0.48
        case .plain: 0.5
        }
    }

    /// Effect at full strength.
    var maxEffect: VoiceEffectParameters {
        switch self {
        case .villainQueen: VoiceEffectParameters(pitchCents: -150, distortionWetDryMix: 0, reverbWetDryMix: 22)
        case .demon: VoiceEffectParameters(pitchCents: -700, distortionWetDryMix: 25, reverbWetDryMix: 30)
        case .plain: .none
        }
    }

    /// Effect scaled by the user's 0–1 strength slider (clamped).
    public func effect(strength: Double) -> VoiceEffectParameters {
        let s = Float(min(max(strength, 0), 1))
        let m = maxEffect
        return VoiceEffectParameters(pitchCents: m.pitchCents * s,
                                     distortionWetDryMix: m.distortionWetDryMix * s,
                                     reverbWetDryMix: m.reverbWetDryMix * s)
    }
}

/// A platform-neutral description of an installed speech voice.
public struct VoiceCandidate: Equatable, Sendable {
    public let id: String
    public let language: String
    public let isFemale: Bool
    /// 1 = default, 2 = enhanced, 3 = premium (AVSpeechSynthesisVoiceQuality raw values).
    public let quality: Int
    public let isPersonal: Bool

    public init(id: String, language: String, isFemale: Bool, quality: Int, isPersonal: Bool) {
        self.id = id
        self.language = language
        self.isFemale = isFemale
        self.quality = quality
        self.isPersonal = isPersonal
    }
}

public enum VoicePicker {
    /// Best voice for a style: preferred language first, then any English; female before male;
    /// higher quality first; personal voices are never auto-picked.
    public static func pick(from voices: [VoiceCandidate], style: VoiceStyle) -> String? {
        let usable = voices.filter { !$0.isPersonal }
        let exact = usable.filter { $0.language == style.preferredLanguage }
        let english = usable.filter { $0.language.hasPrefix("en") }
        let pool = exact.isEmpty ? english : exact
        return pool.max { a, b in
            (a.isFemale ? 1 : 0, a.quality, b.id) < (b.isFemale ? 1 : 0, b.quality, a.id)
        }?.id
    }
}

import Foundation

/// Audio settings for Lucy's "devil" voice, derived from one 0–1 strength slider.
public struct DevilEffectParameters: Equatable, Sendable {
    /// AVAudioUnitTimePitch.pitch, in cents (negative = deeper).
    public let pitchCents: Float
    /// AVAudioUnitDistortion.wetDryMix, 0–100.
    public let distortionWetDryMix: Float
    /// AVAudioUnitReverb.wetDryMix, 0–100.
    public let reverbWetDryMix: Float
}

public enum DevilEffect {
    public static let defaultStrength = 0.6
    static let maxPitchDropCents: Float = 700
    static let maxDistortionMix: Float = 25
    static let maxReverbMix: Float = 30

    public static func parameters(strength: Double) -> DevilEffectParameters {
        let s = Float(min(max(strength, 0), 1))
        return DevilEffectParameters(pitchCents: -maxPitchDropCents * s,
                                     distortionWetDryMix: maxDistortionMix * s,
                                     reverbWetDryMix: maxReverbMix * s)
    }

    /// Below this the effect is inaudible, so plain system speech is used instead.
    public static func isActive(strength: Double) -> Bool { strength > 0.01 }
}

import Foundation

public enum TokenEstimate {
    /// Rough tokenizer-free estimate (~4 UTF-8 bytes per token), rounded up.
    public static func approximate(_ text: String) -> Int { (text.utf8.count + 3) / 4 }
}

public enum PersonaPreset: String, CaseIterable, Codable, Sendable {
    case lucyTyrant, calmCoach, buddy, secretary

    public var title: String {
        switch self {
        case .lucyTyrant: "Lucy — tyrant queen"
        case .calmCoach: "Calm coach"
        case .buddy: "Friendly buddy"
        case .secretary: "Efficient secretary"
        }
    }

    public var instructions: String {
        switch self {
        case .lucyTyrant:
            "You are Lucy, a tyrant queen with a devil's humor. Bossy, sarcastic, teasing; call the user your minion. Always truly helpful and accurate. Keep answers short."
        case .calmCoach:
            "You are Lucy, a calm, encouraging coach. Warm, patient and practical. Keep answers short."
        case .buddy:
            "You are Lucy, the user's easygoing friend. Casual, funny and kind. Keep answers short."
        case .secretary:
            "You are Lucy, an efficient personal secretary. Precise, polite, organized. Keep answers short."
        }
    }

    /// AVSpeechUtterance pitchMultiplier (0.5–2.0).
    public var pitch: Float {
        switch self {
        case .lucyTyrant: 0.85
        case .calmCoach: 0.95
        case .buddy: 1.05
        case .secretary: 1.0
        }
    }

    /// AVSpeechUtterance rate (0–1; system default 0.5).
    public var rate: Float {
        switch self {
        case .lucyTyrant: 0.48
        case .calmCoach: 0.45
        case .buddy: 0.52
        case .secretary: 0.5
        }
    }

    public var sampleLine: String {
        switch self {
        case .lucyTyrant: "Kneel, minion. Your queen is listening. Mwahaha."
        case .calmCoach: "Take a breath. I'm here, let's take it one step at a time."
        case .buddy: "Hey! What's up? Talk to me."
        case .secretary: "Good day. How may I assist you?"
        }
    }
}

public struct Persona: Equatable, Sendable {
    public static let tokenBudget = 150
    static let safetyRule = "If the user says \"serious mode\" or asks about health, safety or emergencies, drop the act and answer plainly and kindly."
    static let maxNameLength = 40

    public var preset: PersonaPreset
    public var userName: String

    public init(preset: PersonaPreset, userName: String) {
        self.preset = preset
        self.userName = userName
    }

    public func systemPrompt() -> String {
        var parts = [preset.instructions]
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            parts.append("The user's name is \(name.prefix(Self.maxNameLength)).")
        }
        parts.append(Self.safetyRule)
        return parts.joined(separator: " ")
    }
}

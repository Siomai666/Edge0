import Foundation
import LucyCore

enum PrefKey {
    static let preset = "lucy.preset"
    static let userName = "lucy.userName"
    static let voiceID = "lucy.voiceID"
    static let speak = "lucy.speakReplies"
    static let faceID = "lucy.faceIDLock"
    static let devilEffect = "lucy.devilEffect"
}

enum AssistantPrefs {
    static var persona: Persona {
        let d = UserDefaults.standard
        let preset = PersonaPreset(rawValue: d.string(forKey: PrefKey.preset) ?? "") ?? .lucyTyrant
        return Persona(preset: preset, userName: d.string(forKey: PrefKey.userName) ?? "")
    }
    static var speakReplies: Bool { UserDefaults.standard.object(forKey: PrefKey.speak) as? Bool ?? true }
    static var voiceID: String? {
        guard let v = UserDefaults.standard.string(forKey: PrefKey.voiceID), !v.isEmpty else { return nil }
        return v
    }
    static var devilEffect: Double {
        UserDefaults.standard.object(forKey: PrefKey.devilEffect) as? Double ?? DevilEffect.defaultStrength
    }
}

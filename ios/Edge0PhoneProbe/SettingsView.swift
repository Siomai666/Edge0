@preconcurrency import AVFoundation
import LucyCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.preset) private var presetRaw = PersonaPreset.lucyTyrant.rawValue
    @AppStorage(PrefKey.userName) private var userName = ""
    @AppStorage(PrefKey.voiceID) private var voiceID = ""
    @AppStorage(PrefKey.speak) private var speakReplies = true
    @AppStorage(PrefKey.faceID) private var faceIDLock = false
    @AppStorage(PrefKey.devilEffect) private var devilEffect = DevilEffect.defaultStrength
    @State private var allLanguages = false
    @State private var personalVoiceNote: String?
    @State private var voiceListVersion = 0
    @StateObject private var preview = VoiceOutput()

    private var preset: PersonaPreset { PersonaPreset(rawValue: presetRaw) ?? .lucyTyrant }

    private var voices: [AVSpeechSynthesisVoice] {
        _ = voiceListVersion   // re-read after Personal Voice permission changes
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { allLanguages || $0.language.hasPrefix("en") || Self.isPersonal($0) }
            .sorted { (Self.rank($0), $0.name) > (Self.rank($1), $1.name) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personality") {
                    Picker("Character", selection: $presetRaw) {
                        ForEach(PersonaPreset.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }
                    TextField("What should Lucy call you?", text: $userName)
                }
                voiceSection
                personalVoiceSection
                Section("Privacy") {
                    Toggle("Lock with Face ID", isOn: $faceIDLock)
                }
                Section("Action Button") {
                    Text("Settings → Action Button → Shortcut → Lucy → Talk to Lucy")
                        .font(.footnote)
                }
            }
            .navigationTitle("Lucy")
            .toolbar { Button("Done") { dismiss() } }
        }
        .onDisappear { preview.stop() }
    }

    private var voiceSection: some View {
        Section {
            Toggle("Speak replies", isOn: $speakReplies)
            Picker("Voice", selection: $voiceID) {
                Text("Default").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text(Self.label(for: voice)).tag(voice.identifier)
                }
            }
            Toggle("Show all languages", isOn: $allLanguages)
            VStack(alignment: .leading, spacing: 4) {
                Text("Devil effect: \(Int((devilEffect * 100).rounded()))%")
                Slider(value: $devilEffect, in: 0...1, step: 0.1)
            }
            Button("Preview voice") { preview.speak(preset.sampleLine) }
        } header: {
            Text("Voice")
        } footer: {
            Text("More voices (Eddy, Flo, Reed, Sandy, Shelley, other accents and character voices): iPhone Settings → Accessibility → Spoken Content → Voices. Download an Enhanced or Premium voice for the best quality, then pick it here.")
        }
    }

    private var personalVoiceSection: some View {
        Section {
            Button("Use my Personal Voice") { requestPersonalVoice() }
            if let personalVoiceNote {
                Text(personalVoiceNote).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Personal Voice")
        } footer: {
            Text("Create one first: iPhone Settings → Accessibility → Personal Voice. It must be recorded by the person whose voice it is, with their consent.")
        }
    }

    private func requestPersonalVoice() {
        Task {
            let status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
            switch status {
            case .authorized: personalVoiceNote = "Allowed. Your Personal Voice now appears in the Voice list."
            case .denied: personalVoiceNote = "Not allowed. Change it in iPhone Settings → Lucy."
            case .unsupported: personalVoiceNote = "Personal Voice isn't supported on this iPhone."
            default: personalVoiceNote = "No Personal Voice found. Create one in iPhone Settings first."
            }
            voiceListVersion += 1
        }
    }

    private static func isPersonal(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.voiceTraits.contains(.isPersonalVoice)
    }

    /// Personal voices first, then Premium, Enhanced, Default.
    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        isPersonal(voice) ? 10 : voice.quality.rawValue
    }

    private static func label(for voice: AVSpeechSynthesisVoice) -> String {
        if isPersonal(voice) { return "\(voice.name) · Personal Voice" }
        let tier: String
        switch voice.quality {
        case .premium: tier = " · Premium"
        case .enhanced: tier = " · Enhanced"
        default: tier = ""
        }
        return "\(voice.name) (\(voice.language))\(tier)"
    }
}

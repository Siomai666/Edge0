# Lucy Build 1 — Voice + Siri Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lucy listens (on-device speech), answers in her tyrant persona, speaks replies aloud, opens listening from the Action Button, and can be locked with Face ID.

**Architecture:** New standalone SwiftPM package `ios/LucyCore` (pure Swift) holds persona prompts and speech chunking, unit-tested on the CI Mac. The app target gains small single-purpose files (prefs, audio session, voice in/out, intents, settings, lock) and links `LucyCore` as a second local package. The 8B engine gets an optional `systemPrompt` injected into its existing `<role>SYSTEM</role>` block on the first turn only.

**Tech Stack:** Swift 6, SwiftUI, Speech (on-device), AVFoundation, AppIntents, LocalAuthentication, XCTest, GitHub Actions macOS runner.

## Global Constraints
- Deployment target iOS 17.0; device iPhone 17e; app target `SWIFT_VERSION = 6.0`.
- Bundle ID stays `com.siomai666.edge0phone`; display name `Lucy`.
- Offline only: `requiresOnDeviceRecognition = true`; no network calls.
- Persona system prompt ≤ 150 estimated tokens (ceil(utf8 bytes / 4)); Lucy preset ≤ 80.
- Lucy hard limits: helpful + accurate; drops the act for "serious mode", health, safety, emergencies.
- No paid entitlements (free Apple ID signing).
- No local Mac: compile/test only in CI (`.github/workflows/build-ios.yml`). Expect Swift 6 concurrency diagnostics to fix from the CI log.
- Commits: author `Siomai666 <Siomai666@users.noreply.github.com>`, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File Map
| Path | Responsibility |
|---|---|
| `ios/LucyCore/Package.swift` | standalone package, product `LucyCore` |
| `ios/LucyCore/Sources/LucyCore/Persona.swift` | presets, system prompt, token estimate |
| `ios/LucyCore/Sources/LucyCore/SpeechChunker.swift` | streamed text → speakable sentences; markdown cleanup |
| `ios/LucyCore/Tests/LucyCoreTests/*.swift` | unit tests |
| `ios/Sources/Edge0MLX/Edge0ChatEngine.swift` | `systemPrompt` parameter |
| `ios/Edge0PhoneProbe/AssistantPrefs.swift` | UserDefaults keys + typed reads |
| `ios/Edge0PhoneProbe/AudioSession.swift` | AVAudioSession modes |
| `ios/Edge0PhoneProbe/VoiceOutput.swift` | text-to-speech |
| `ios/Edge0PhoneProbe/VoiceInput.swift` | speech-to-text, silence auto-stop |
| `ios/Edge0PhoneProbe/LucyIntents.swift` | "Talk to Lucy" App Intent + App Shortcut |
| `ios/Edge0PhoneProbe/SettingsView.swift` | persona / voice / lock settings |
| `ios/Edge0PhoneProbe/LockGate.swift` | Face ID gate |
| `ios/Edge0PhoneProbe/ContentView.swift` | wire-up |
| `ios/Edge0PhoneProbe/Info.plist` | usage descriptions |
| `ios/tools/pbx_add_lucy.py` | adds files + LucyCore package to project.pbxproj |
| `.github/workflows/build-ios.yml` | run LucyCore tests before build |

---

### Task 1: LucyCore package — Persona

**Files:** Create `ios/LucyCore/Package.swift`, `ios/LucyCore/Sources/LucyCore/Persona.swift`, `ios/LucyCore/Tests/LucyCoreTests/PersonaTests.swift`

**Produces:** `PersonaPreset` (`lucyTyrant, calmCoach, buddy, secretary`; `.title`, `.instructions`, `.pitch: Float`, `.rate: Float`, `.sampleLine`), `Persona(preset:userName:)`, `Persona.systemPrompt() -> String`, `Persona.tokenBudget = 150`, `TokenEstimate.approximate(_:) -> Int`.

- [ ] **Step 1: Package manifest**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LucyCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LucyCore", targets: ["LucyCore"])],
    targets: [
        .target(name: "LucyCore"),
        .testTarget(name: "LucyCoreTests", dependencies: ["LucyCore"]),
    ]
)
```
- [ ] **Step 2: Tests**
```swift
import XCTest
@testable import LucyCore

final class PersonaTests: XCTestCase {
    func testLucyPromptIsShortAndInCharacter() {
        let prompt = Persona(preset: .lucyTyrant, userName: "").systemPrompt()
        XCTAssertTrue(prompt.contains("Lucy"))
        XCTAssertTrue(prompt.contains("tyrant"))
        XCTAssertTrue(prompt.contains("serious mode"))
        XCTAssertLessThanOrEqual(TokenEstimate.approximate(prompt), 80)
    }

    func testUserNameIsIncludedAndTruncated() {
        let long = String(repeating: "x", count: 100)
        let prompt = Persona(preset: .lucyTyrant, userName: "  \(long)  ").systemPrompt()
        XCTAssertTrue(prompt.contains(String(repeating: "x", count: 40)))
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: 41)))
    }

    func testBlankUserNameIsOmitted() {
        XCTAssertFalse(Persona(preset: .buddy, userName: "   ").systemPrompt().contains("user's name"))
    }

    func testEveryPresetFitsBudget() {
        for preset in PersonaPreset.allCases {
            let prompt = Persona(preset: preset, userName: String(repeating: "n", count: 40)).systemPrompt()
            XCTAssertLessThanOrEqual(TokenEstimate.approximate(prompt), Persona.tokenBudget, "\(preset)")
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertFalse(preset.sampleLine.isEmpty)
            XCTAssertTrue((0.5...2.0).contains(preset.pitch))
            XCTAssertTrue((0.0...1.0).contains(preset.rate))
        }
    }

    func testTokenEstimateRoundsUp() {
        XCTAssertEqual(TokenEstimate.approximate(""), 0)
        XCTAssertEqual(TokenEstimate.approximate("abcde"), 2)
    }
}
```
- [ ] **Step 3: Implementation**
```swift
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
```
- [ ] **Step 4: Commit** `feat(lucy): LucyCore package with persona presets`

### Task 2: LucyCore — SpeechChunker

**Files:** Create `ios/LucyCore/Sources/LucyCore/SpeechChunker.swift`, `ios/LucyCore/Tests/LucyCoreTests/SpeechChunkerTests.swift`

**Produces:** `struct SpeechChunker { init(); mutating func take(from fullText: String, final: Bool) -> [String] }`, `enum SpeechText { static func clean(_:) -> String }`.

- [ ] **Step 1: Tests**
```swift
import XCTest
@testable import LucyCore

final class SpeechChunkerTests: XCTestCase {
    func testEmitsCompletedSentencesIncrementally() {
        var c = SpeechChunker()
        XCTAssertEqual(c.take(from: "Hello there. How", final: false), ["Hello there."])
        XCTAssertEqual(c.take(from: "Hello there. How are you? I", final: false), ["How are you?"])
        XCTAssertEqual(c.take(from: "Hello there. How are you? I am fine", final: true), ["I am fine"])
    }

    func testDoesNotSplitDecimals() {
        var c = SpeechChunker()
        XCTAssertEqual(c.take(from: "It took 3.5 hours", final: false), [])
        XCTAssertEqual(c.take(from: "It took 3.5 hours.", final: true), ["It took 3.5 hours."])
    }

    func testNewlineEndsChunkAndBlankChunksAreDropped() {
        var c = SpeechChunker()
        XCTAssertEqual(c.take(from: "Line one\n\nLine two\n", final: false), ["Line one", "Line two"])
    }

    func testShrunkTextResets() {
        var c = SpeechChunker()
        _ = c.take(from: "Long sentence here. ", final: false)
        XCTAssertEqual(c.take(from: "New.", final: true), ["New."])
    }

    func testCleanStripsMarkdown() {
        XCTAssertEqual(SpeechText.clean("**Bold** and `code` # Title - item"), "Bold and code Title item")
        XCTAssertEqual(SpeechText.clean("  ***  "), "")
    }
}
```
- [ ] **Step 2: Implementation**
```swift
import Foundation

/// Turns a growing, streamed reply into whole sentences for text-to-speech.
public struct SpeechChunker: Sendable {
    private var consumed = 0
    private static let terminators: Set<Character> = [".", "!", "?", "。", "！", "？"]

    public init() {}

    public mutating func take(from fullText: String, final: Bool) -> [String] {
        let chars = Array(fullText)
        if consumed > chars.count { consumed = 0 }
        var out: [String] = []
        var start = consumed
        var i = consumed
        while i < chars.count {
            let ch = chars[i]
            let atEnd = i + 1 == chars.count
            let ends = ch == "\n"
                || (Self.terminators.contains(ch) && (atEnd ? final : chars[i + 1].isWhitespace))
            if ends {
                append(String(chars[start...i]), to: &out)
                start = i + 1
            }
            i += 1
        }
        if final, start < chars.count {
            append(String(chars[start...]), to: &out)
            start = chars.count
        }
        consumed = start
        return out
    }

    private func append(_ raw: String, to out: inout [String]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !SpeechText.clean(trimmed).isEmpty { out.append(trimmed) }
    }
}

public enum SpeechText {
    /// Removes markdown symbols that a speech voice would read aloud.
    public static func clean(_ text: String) -> String {
        var s = text
        for token in ["**", "__", "`", "#", "*"] { s = s.replacingOccurrences(of: token, with: "") }
        s = s.replacingOccurrences(of: " - ", with: " ")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```
- [ ] **Step 3: Commit** `feat(lucy): speech chunker for streamed replies`

### Task 3: CI runs LucyCore tests

**Files:** Modify `.github/workflows/build-ios.yml` — insert before step "Download Edge0 8B weights into Models/":
```yaml
      - name: LucyCore unit tests
        run: swift test --package-path LucyCore
```
- [ ] Push Tasks 1–3, run workflow; expect `Executed 10 tests, with 0 failures`. Fix and repeat if red.
- [ ] **Commit** `ci: run LucyCore tests before iOS build`

### Task 4: Engine `systemPrompt` hook

**Files:** Modify `ios/Sources/Edge0MLX/Edge0ChatEngine.swift`
**Produces:** `Edge0ChatEngine.reply(to:maxTokens:thinking:seed:systemPrompt:onText:shouldContinue:)`; used only when no conversation context exists yet.

- [ ] **Step 1:** Replace `firstTurn`:
```swift
    static func firstTurn(_ text: String, thinking: Bool, system: String? = nil) -> String {
        let persona = system?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let prefix = persona.isEmpty ? "" : persona + "\n"
        return "<role>SYSTEM</role>\(prefix)detailed thinking \(thinking ? "on" : "off")<|role_end|>" +
            "<role>HUMAN</role>\(text)<|role_end|>" + assistantPrefix(thinking: thinking)
    }
```
- [ ] **Step 2:** `reply(...)` gains `systemPrompt: String? = nil` after `seed`, forwarded to `generateReply`; `generateReply` gains the same parameter and calls `Edge0ChatTemplate8B.firstTurn(trimmed, thinking: thinking, system: systemPrompt)`.
- [ ] **Step 3: Commit** `feat(engine): optional system prompt on first turn`

### Task 5: App plumbing — prefs, audio session, Info.plist, project wiring

**Files:** Create `ios/Edge0PhoneProbe/AssistantPrefs.swift`, `ios/Edge0PhoneProbe/AudioSession.swift`, `ios/tools/pbx_add_lucy.py`; modify `Info.plist`, `project.pbxproj`.
**Produces:** `PrefKey.{preset,userName,voiceID,speak,faceID}`, `AssistantPrefs.persona`, `.speakReplies`, `.voiceID`; `AudioSession.activateForRecording() throws`, `AudioSession.activateForPlayback()`.

- [ ] **Step 1: `AssistantPrefs.swift`**
```swift
import Foundation
import LucyCore

enum PrefKey {
    static let preset = "lucy.preset"
    static let userName = "lucy.userName"
    static let voiceID = "lucy.voiceID"
    static let speak = "lucy.speakReplies"
    static let faceID = "lucy.faceIDLock"
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
}
```
- [ ] **Step 2: `AudioSession.swift`**
```swift
@preconcurrency import AVFoundation

enum AudioSession {
    static func activateForRecording() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func activateForPlayback() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? s.setActive(true)
    }
}
```
- [ ] **Step 3: Info.plist** — insert before `<key>UIApplicationSceneManifest</key>`:
```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Lucy listens when you press the mic or the Action Button.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Lucy turns your voice into text on this iPhone. Nothing leaves the device.</string>
	<key>NSFaceIDUsageDescription</key>
	<string>Lock Lucy so only you can open her.</string>
```
- [ ] **Step 4: `ios/tools/pbx_add_lucy.py`**, then run `python ios/tools/pbx_add_lucy.py` → `patched` (re-run → `already patched`)
```python
"""Adds Lucy build-1 sources and the LucyCore local package to the Xcode project (idempotent)."""
import sys
from pathlib import Path

P = Path(__file__).resolve().parents[1] / "Edge0PhoneProbe.xcodeproj" / "project.pbxproj"
FILES = ["AssistantPrefs.swift", "AudioSession.swift", "VoiceOutput.swift", "VoiceInput.swift",
         "LucyIntents.swift", "SettingsView.swift", "LockGate.swift"]


def sub(s, anchor, insert, after=True):
    if anchor not in s:
        sys.exit(f"anchor not found: {anchor!r}")
    return s.replace(anchor, anchor + insert if after else insert + anchor, 1)


s = P.read_text(encoding="utf-8")
if "LucyCore" in s:
    print("already patched")
    sys.exit(0)
bf = fr = grp = src = ""
for k, name in enumerate(FILES, 1):
    f, b = f"A0000000000000000000C{k:03d}", f"A0000000000000000000D{k:03d}"
    bf += f"\t\t{b} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {f} /* {name} */; }};\n"
    fr += (f"\t\t{f} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
           f"path = {name}; sourceTree = \"<group>\"; }};\n")
    grp += f"\t\t\t\t{f} /* {name} */,\n"
    src += f"\t\t\t\t{b} /* {name} in Sources */,\n"
bf += ("\t\tA0000000000000000000E103 /* LucyCore in Frameworks */ = {isa = PBXBuildFile; "
       "productRef = A0000000000000000000E102 /* LucyCore */; };\n")
s = sub(s, "/* End PBXBuildFile section */", bf, after=False)
s = sub(s, "/* End PBXFileReference section */", fr, after=False)
s = sub(s, "\t\t\t\tA00000000000000000000012 /* ContentView.swift */,\n", grp)
s = sub(s, "\t\t\t\tA00000000000000000000002 /* ContentView.swift in Sources */,\n", src)
s = sub(s, "\t\t\t\tA00000000000000000000005 /* Edge0MLX in Frameworks */,\n",
        "\t\t\t\tA0000000000000000000E103 /* LucyCore in Frameworks */,\n")
s = sub(s, "\t\t\t\tA00000000000000000000072 /* Edge0MLX */,\n",
        "\t\t\t\tA0000000000000000000E102 /* LucyCore */,\n")
s = sub(s, "\t\t\t\tA00000000000000000000081 /* XCLocalSwiftPackageReference \".\" */,\n",
        "\t\t\t\tA0000000000000000000E101 /* XCLocalSwiftPackageReference \"LucyCore\" */,\n")
s = sub(s, "/* End XCLocalSwiftPackageReference section */",
        "\t\tA0000000000000000000E101 /* XCLocalSwiftPackageReference \"LucyCore\" */ = {\n"
        "\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = LucyCore;\n\t\t};\n", after=False)
s = sub(s, "/* End XCSwiftPackageProductDependency section */",
        "\t\tA0000000000000000000E102 /* LucyCore */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tpackage = A0000000000000000000E101 /* XCLocalSwiftPackageReference \"LucyCore\" */;\n"
        "\t\t\tproductName = LucyCore;\n\t\t};\n", after=False)
P.write_text(s, encoding="utf-8", newline="\n")
print("patched")
```
- [ ] **Step 5: Commit** `feat(lucy): prefs, audio session, permissions, project wiring`

### Task 6: VoiceOutput (text-to-speech)

**Files:** Create `ios/Edge0PhoneProbe/VoiceOutput.swift`
**Produces:** `@MainActor final class VoiceOutput: ObservableObject` — `beginReply()`, `feed(_ fullText: String, final: Bool)`, `speak(_:)`, `stop()`, `@Published isSpeaking`.
```swift
@preconcurrency import AVFoundation
import Foundation
import LucyCore

@MainActor
final class VoiceOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synth = AVSpeechSynthesizer()
    private var chunker = SpeechChunker()

    override init() {
        super.init()
        synth.delegate = self
    }

    func beginReply() {
        stop()
        chunker = SpeechChunker()
    }

    func feed(_ fullText: String, final: Bool) {
        guard AssistantPrefs.speakReplies else { return }
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
        synth.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = self.synth.isSpeaking }
    }
}
```
- [ ] **Commit** `feat(lucy): spoken replies`

### Task 7: VoiceInput (speech-to-text)

**Files:** Create `ios/Edge0PhoneProbe/VoiceInput.swift`
**Produces:** `@MainActor final class VoiceInput: ObservableObject` — `enum State { idle, listening, unavailable(String) }`, `@Published state`, `@Published transcript`, `start(onFinish:) async`, `finish()`, `cancel()`.
```swift
@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
final class VoiceInput: ObservableObject {
    enum State: Equatable { case idle, listening, unavailable(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var onFinish: ((String) -> Void)?
    private static let silenceTimeout: Duration = .milliseconds(1600)

    func start(onFinish: @escaping (String) -> Void) async {
        guard state != .listening else { return }
        guard await Self.authorize() else {
            state = .unavailable("Allow Microphone and Speech Recognition for Lucy in Settings.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("On-device speech recognition isn't available. Type instead.")
            return
        }
        do {
            try AudioSession.activateForRecording()
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.requiresOnDeviceRecognition = true
            req.shouldReportPartialResults = true
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            request = req
            transcript = ""
            self.onFinish = onFinish
            state = .listening
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failed: failed) }
            }
            armSilenceTimer()
        } catch {
            stopAudio()
            state = .unavailable("Microphone error: \(error.localizedDescription)")
        }
    }

    func finish() {
        guard state == .listening else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinish
        onFinish = nil
        stopAudio()
        state = .idle
        if !text.isEmpty { callback?(text) }
    }

    func cancel() {
        onFinish = nil
        stopAudio()
        state = .idle
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard state == .listening else { return }
        if let text, !text.isEmpty {
            transcript = text
            armSilenceTimer()
        }
        if isFinal || failed { finish() }
    }

    private func armSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.silenceTimeout)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func stopAudio() {
        silenceTimer?.cancel()
        silenceTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private static func authorize() async -> Bool {
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
```
- [ ] **Commit** `feat(lucy): on-device voice input with silence auto-stop`

### Task 8: "Talk to Lucy" App Intent

**Files:** Create `ios/Edge0PhoneProbe/LucyIntents.swift`
**Produces:** `ListenRequest.pending` (MainActor Bool), `ListenRequest.notification`.
```swift
import AppIntents
import Foundation

enum ListenRequest {
    @MainActor static var pending = false
    static let notification = Notification.Name("LucyListenRequested")
}

struct TalkToLucyIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Lucy"
    static let description = IntentDescription("Opens Lucy and starts listening.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenRequest.pending = true
        NotificationCenter.default.post(name: ListenRequest.notification, object: nil)
        return .result()
    }
}

struct LucyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TalkToLucyIntent(),
                    phrases: ["Talk to \(.applicationName)", "Hey \(.applicationName)"],
                    shortTitle: "Talk to Lucy",
                    systemImageName: "mic.fill")
    }
}
```
- [ ] **Commit** `feat(lucy): Talk to Lucy intent for Action Button and Siri`

### Task 9: Face ID lock + Settings screen

**Files:** Create `ios/Edge0PhoneProbe/LockGate.swift`, `ios/Edge0PhoneProbe/SettingsView.swift`
```swift
import Foundation
import LocalAuthentication

@MainActor
final class LockGate: ObservableObject {
    @Published private(set) var isLocked = UserDefaults.standard.bool(forKey: PrefKey.faceID)

    func lockIfEnabled() {
        if UserDefaults.standard.bool(forKey: PrefKey.faceID) { isLocked = true }
    }

    func unlock() async {
        guard isLocked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false   // no passcode/biometrics configured: never trap the user
            return
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: "Unlock Lucy")) ?? false
        isLocked = !ok
    }
}
```
```swift
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
    @StateObject private var preview = VoiceOutput()

    private var preset: PersonaPreset { PersonaPreset(rawValue: presetRaw) ?? .lucyTyrant }

    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
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
                Section {
                    Toggle("Speak replies", isOn: $speakReplies)
                    Picker("Voice", selection: $voiceID) {
                        Text("Default").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text(label(for: voice)).tag(voice.identifier)
                        }
                    }
                    Button("Preview voice") { preview.speak(preset.sampleLine) }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("For a better voice: Settings → Accessibility → Spoken Content → Voices → English, download an Enhanced or Premium voice, then pick it here.")
                }
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

    private func label(for voice: AVSpeechSynthesisVoice) -> String {
        let tier: String
        switch voice.quality {
        case .premium: tier = " · Premium"
        case .enhanced: tier = " · Enhanced"
        default: tier = ""
        }
        return "\(voice.name) (\(voice.language))\(tier)"
    }
}
```
- [ ] **Commit** `feat(lucy): settings screen and Face ID lock`

### Task 10: Wire into ContentView

**Files:** Modify `ios/Edge0PhoneProbe/ContentView.swift`
- [ ] **Step 1:** add `import LucyCore`.
- [ ] **Step 2 — ChatRuntime.reply:** add parameter `systemPrompt: String? = nil`; pass `systemPrompt: systemPrompt` into both `.edge8` `engine.reply` calls (35B unchanged).
- [ ] **Step 3 — ChatViewModel:** add `let voice = VoiceOutput()`. In `send(maxTokens:)`: call `voice.beginReply()` before creating the task; pass `systemPrompt: selectedModel == .edge8 ? AssistantPrefs.persona.systemPrompt() : nil` to the first `runtime.reply`; in the `onText` main-actor closure after `self.messages[index].text = partial` add `self.voice.feed(partial, final: false)`; after the final message text is set add `voice.feed(result.text, final: true)`. Add `voice.stop()` to `stop()`, `newConversation()`, `chooseAnotherModel()`.
- [ ] **Step 4 — ContentView state:**
```swift
    @StateObject private var listener = VoiceInput()
    @StateObject private var lock = LockGate()
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase
```
and suggestions:
```swift
    private let suggestions = [
        "What should I do first today, my queen?",
        "Roast my to-do list",
        "Give me a 5-minute break plan",
        "Teach me one useful thing",
    ]
```
- [ ] **Step 5 — helper:**
```swift
    private func startListening() {
        guard chat.phase == .ready, listener.state != .listening else { return }
        chat.voice.stop()
        Task {
            await listener.start { text in
                chat.input = text
                chat.send()
            }
        }
    }
```
- [ ] **Step 6 — body modifiers** after the existing `.task { ... }`:
```swift
        .task {
            // Assistant mode: open straight into Lucy 8B unless a bench/smoke flag chose a model.
            let flagged = CommandLine.arguments.contains {
                $0.hasPrefix("--model=") || $0.hasPrefix("--bench") || $0.hasPrefix("--smoke")
            }
            if !flagged, chat.selectedModel == nil, chat.isInstalled(.edge8) {
                chat.choose(.edge8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ListenRequest.notification)) { _ in
            if chat.phase == .ready {
                ListenRequest.pending = false
                startListening()
            }
        }
        .onChange(of: chat.phase) {
            if chat.phase == .ready, ListenRequest.pending {
                ListenRequest.pending = false
                startListening()
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background: lock.lockIfEnabled()
            case .active: Task { await lock.unlock() }
            default: break
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .overlay { if listener.state == .listening { listeningOverlay } }
        .overlay { if lock.isLocked { lockedOverlay } }
```
- [ ] **Step 7 — overlays:**
```swift
    private var listeningOverlay: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative)
            Text(listener.transcript.isEmpty ? "Speak, minion…" : listener.transcript)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            HStack(spacing: 14) {
                Button("Cancel") { listener.cancel() }
                    .buttonStyle(.bordered)
                Button("Done") { listener.finish() }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.88))
    }

    private var lockedOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.red)
            Text("Lucy is locked").font(.title2.weight(.semibold))
            Button("Unlock") { Task { await lock.unlock() } }
                .buttonStyle(.borderedProminent).tint(.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
```
- [ ] **Step 8 — header:** before the switch-model button:
```swift
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Settings")
```
- [ ] **Step 9 — composer:** make the outer container `VStack(spacing: 6) { <voice error text>; HStack { mic, TextField, send } }` where
```swift
            if case .unavailable(let reason) = listener.state {
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
```
and the mic button (first in the HStack):
```swift
            Button(action: startListening) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 45, height: 45)
                    .background(Color.red.opacity(0.85), in: Circle())
            }
            .disabled(chat.phase != .ready)
            .opacity(chat.phase == .ready ? 1 : 0.5)
            .accessibilityLabel("Talk to Lucy")
```
- [ ] **Step 10 — welcome:** `Text("edge0")` → `Text("Lucy")`; subtitle → `"Your tyrant queen. Offline, on your iPhone."`.
- [ ] **Step 11: Commit** `feat(lucy): voice assistant UI, auto-load, settings, lock`

### Task 11: CI build + device checklist

- [ ] Push; run workflow; fix compile errors from the log (expected: Swift 6 isolation diagnostics) until green.
- [ ] Download artifact as `Lucy.ipa`; user installs via Sideloadly (same bundle ID → model stays).
- [ ] **Device checklist (user):**
  1. App opens straight into Lucy 8B (no picker) and loads.
  2. Tap mic → allow Microphone + Speech → say "who are you" → text appears, auto-sends after ~1.6 s silence.
  3. Lucy answers bossy/teasing and speaks aloud; report the TTFT number under the first reply.
  4. Say "serious mode, I cut my hand" → plain, kind answer.
  5. Gear → change voice → Preview; set your name → new chat → Lucy uses it.
  6. iPhone Settings → Action Button → Shortcut → Lucy → Talk to Lucy; press button → app opens listening.
  7. Enable Face ID lock → leave app → reopen → Face ID prompt.

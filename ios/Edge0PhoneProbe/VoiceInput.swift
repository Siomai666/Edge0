@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// On-device speech-to-text. Stops by itself after a short silence.
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

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
            guard Self.installTap(on: input, feeding: req) else {
                state = .unavailable("No microphone input available right now.")
                return
            }
            engine.prepare()
            try engine.start()
            request = req
            transcript = ""
            self.onFinish = onFinish
            state = .listening
            task = Self.recognize(with: recognizer, request: req) { [weak self] text, isFinal, failed in
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

    // The callbacks below are invoked by iOS on background / real-time audio threads. They must
    // be created in a nonisolated context: a closure formed inside this @MainActor class inherits
    // main-actor isolation, and Swift 6 traps at runtime when iOS calls it off the main thread.

    private nonisolated static func authorize() async -> Bool {
        let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest
    ) -> Bool {
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        return true
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}

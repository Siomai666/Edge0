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

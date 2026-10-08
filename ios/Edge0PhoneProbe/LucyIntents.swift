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

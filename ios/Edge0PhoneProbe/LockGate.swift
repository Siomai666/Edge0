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

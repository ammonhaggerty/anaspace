import Foundation

enum PermissionState: String, Codable {
    case undetermined
    case granted
    case denied
}

struct PermissionStatus: Codable {
    var appleSignIn: PermissionState = .undetermined
    var appleMusic: PermissionState = .undetermined
    var location: PermissionState = .undetermined
    var microphone: PermissionState = .undetermined
    var notifications: PermissionState = .undetermined
}

@Observable @MainActor
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet { LocalStore.shared.saveOnboardingComplete(hasCompletedOnboarding) }
    }
    var currentPermissions: PermissionStatus

    init() {
        let store = LocalStore.shared
        self.hasCompletedOnboarding = store.loadOnboardingComplete()
        self.currentPermissions = PermissionStatus()
    }
}

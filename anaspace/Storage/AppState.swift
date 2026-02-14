import Foundation

@Observable @MainActor
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet { LocalStore.shared.saveOnboardingComplete(hasCompletedOnboarding) }
    }

    init() {
        self.hasCompletedOnboarding = LocalStore.shared.loadOnboardingComplete()
    }
}

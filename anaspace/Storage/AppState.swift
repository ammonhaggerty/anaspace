import Foundation

@Observable @MainActor
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet { LocalStore.shared.saveOnboardingComplete(hasCompletedOnboarding) }
    }

    var autoplayEnabled: Bool {
        didSet { LocalStore.shared.saveAutoplay(autoplayEnabled) }
    }

    init() {
        self.hasCompletedOnboarding = LocalStore.shared.loadOnboardingComplete()
        self.autoplayEnabled = LocalStore.shared.loadAutoplay()
    }
}

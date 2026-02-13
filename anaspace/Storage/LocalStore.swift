import Foundation

@MainActor
final class LocalStore {
    static let shared = LocalStore()

    private let defaults = UserDefaults.standard
    private let onboardingKey = "hasCompletedOnboarding"

    private var engagementFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("engagements.json")
    }

    // MARK: - Onboarding

    func loadOnboardingComplete() -> Bool {
        defaults.bool(forKey: onboardingKey)
    }

    func saveOnboardingComplete(_ value: Bool) {
        defaults.set(value, forKey: onboardingKey)
    }

    // MARK: - Preferences

    func loadPreferences() -> UserPreferences {
        guard let data = defaults.data(forKey: "userPreferences"),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data)
        else { return UserPreferences() }
        return prefs
    }

    func savePreferences(_ prefs: UserPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: "userPreferences")
        }
    }

    // MARK: - Engagement History

    func appendEngagement(_ entry: EngagementEntry) {
        var history = loadEngagementHistory()
        history.append(entry)
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: engagementFileURL, options: .atomic)
        }
    }

    func loadEngagementHistory() -> [EngagementEntry] {
        guard let data = try? Data(contentsOf: engagementFileURL),
              let entries = try? JSONDecoder().decode([EngagementEntry].self, from: data)
        else { return [] }
        return entries
    }
}

// MARK: - Data Models

struct UserPreferences: Codable {
    var notificationsEnabled: Bool = false
}

struct EngagementEntry: Codable {
    let content: String
    let timestamp: Date
}

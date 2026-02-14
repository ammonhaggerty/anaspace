import Foundation

// MARK: - Claude Model

/// Model tier for Claude API calls
enum ClaudeModel: String, Sendable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-5-20250929"
}

// MARK: - Culture Map Response

/// Stubbed culture map response
struct CultureMapResponse: Sendable {
    let subject: String
    let subjectType: String
    let place: String
    let year: Int
    let narrative: String
    let connections: [CultureConnection]
}

struct CultureConnection: Sendable {
    let name: String
    let relationship: String  // "influenced", "contemporary", "collaborator", etc.
    let relevance: Double     // 0.0 - 1.0
}

// MARK: - Claude Service

@Observable
@MainActor
final class ClaudeService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = true
    var apiKey: String?

    // MARK: - ObservationService Conformance

    func activate() async throws {
        // Load API key from bundle
        apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        isAvailable = apiKey != nil && apiKey?.isEmpty == false
    }

    func deactivate() {}

    // MARK: - Public Methods

    /// Build a culture map from observation signals.
    /// STUB: Returns mock data. Real implementation in next phase.
    func buildCultureMap(from signals: ObservationSignals) async throws -> CultureMapResponse {
        // Simulate network delay
        try await Task.sleep(for: .seconds(1))

        let subject = signals.shazamResult?.artist ?? signals.transcript?.text ?? "Unknown"
        let year = signals.shazamResult?.releaseYear ?? Calendar.current.component(.year, from: signals.timestamp)
        let place = signals.location?.city ?? "Unknown"

        return CultureMapResponse(
            subject: subject,
            subjectType: "person",
            place: place,
            year: year,
            narrative: "A cultural exploration of \(subject) in \(place), \(year).",
            connections: [
                CultureConnection(name: "Connection 1", relationship: "influenced", relevance: 0.9),
                CultureConnection(name: "Connection 2", relationship: "contemporary", relevance: 0.7),
                CultureConnection(name: "Connection 3", relationship: "collaborator", relevance: 0.6),
            ]
        )
    }
}

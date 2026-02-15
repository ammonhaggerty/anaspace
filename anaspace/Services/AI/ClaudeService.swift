import Foundation

// MARK: - Claude Model

/// Model tier for Claude API calls
enum ClaudeModel: String, Sendable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-5-20250929"
}

// MARK: - Culture Map Response

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

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let model = ClaudeModel.sonnet

    // Placeholder system prompt — prompt design is future work
    private let systemPrompt = """
    You are a cultural context engine. Given observation signals (music, speech, location), \
    return a JSON object with these fields: subject, subjectType, place, year, narrative, \
    connections (array of {name, relationship, relevance}). Be concise and insightful.
    """

    // MARK: - ObservationService Conformance

    func activate() async throws {
        apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        isAvailable = apiKey != nil && apiKey?.isEmpty == false
    }

    func deactivate() {}

    // MARK: - Public API

    /// Send observation signals to Claude and return a single result.
    func processObservation(from signals: ObservationSignals) async throws -> ClaudeResult {
        let userMessage = buildUserMessage(from: signals)
        print("[Claude] Request: \(userMessage)")

        let request = try buildRequest(userMessage: userMessage)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.noResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            print("[Claude] API error \(httpResponse.statusCode): \(body)")
            throw ClaudeServiceError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeServiceError.noResponse
        }

        // Extract text from the Messages API response
        let text = extractResponseText(from: json)
        print("[Claude] Response: \(text)")
        return parseClaudeResponse(text)
    }

    // MARK: - User Message Construction

    private func buildUserMessage(from signals: ObservationSignals) -> String {
        var parts: [String] = []

        if let shazam = signals.shazamResult {
            var musicLine = "Music identified: \(shazam.title) by \(shazam.artist)"
            if let album = shazam.album { musicLine += ", Album: \(album)" }
            if let year = shazam.releaseYear { musicLine += ", Released: \(year)" }
            if !shazam.genres.isEmpty { musicLine += ", Genres: \(shazam.genres.joined(separator: ", "))" }
            parts.append(musicLine)
        }

        if let transcript = signals.transcript, !transcript.text.isEmpty {
            parts.append("User said: \(transcript.text)")
        }

        if let location = signals.location {
            let label = LocationService.displayLabel(for: location)
            parts.append("Location: \(label)")
        }

        if parts.isEmpty {
            let label = signals.location.map { LocationService.displayLabel(for: $0) } ?? "unknown location"
            return "Silent observation at: \(label)"
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - API Request

    private func buildRequest(userMessage: String) throws -> URLRequest {
        guard let key = apiKey, !key.isEmpty else {
            throw ClaudeServiceError.noApiKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Extraction

    /// Extract the assistant's text from the Messages API response.
    private func extractResponseText(from json: [String: Any]) -> String {
        guard let content = json["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { block in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
    }

    // MARK: - Response Parsing

    private func parseClaudeResponse(_ text: String) -> ClaudeResult {
        // Try to parse as JSON first
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ClaudeResult(
                subject: json["subject"] as? String ?? "Unknown",
                subjectType: json["subjectType"] as? String ?? "unknown",
                place: json["place"] as? String ?? "Unknown",
                year: json["year"] as? Int ?? Calendar.current.component(.year, from: .now),
                narrative: json["narrative"] as? String ?? text,
                connections: parseConnections(json["connections"]),
                isStreaming: false
            )
        }

        // Fallback: treat the entire text as narrative
        return ClaudeResult(
            subject: "Observation",
            subjectType: "unknown",
            place: "Unknown",
            year: Calendar.current.component(.year, from: .now),
            narrative: text,
            connections: [],
            isStreaming: false
        )
    }

    private func parseConnections(_ raw: Any?) -> [CultureConnection] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let name = item["name"] as? String,
                  let relationship = item["relationship"] as? String else { return nil }
            let relevance = item["relevance"] as? Double ?? 0.5
            return CultureConnection(name: name, relationship: relationship, relevance: relevance)
        }
    }

    // MARK: - Legacy stub (kept for compatibility during transition)

    func buildCultureMap(from signals: ObservationSignals) async throws -> CultureMapResponse {
        let result = try await processObservation(from: signals)
        return CultureMapResponse(
            subject: result.subject,
            subjectType: result.subjectType,
            place: result.place,
            year: result.year,
            narrative: result.narrative,
            connections: result.connections
        )
    }
}

// MARK: - Errors

enum ClaudeServiceError: Error {
    case noApiKey
    case noResponse
    case apiError(statusCode: Int, body: String)
}

import Foundation

// MARK: - Prompt Harness Data Model

/// A location + year pair used throughout the harness.
struct LocationYear: Sendable {
    let location: String
    let year: Int
}

struct PromptTestCase: Sendable {
    let questionType: String      // "subject", "collaborator", "peer", "influence", "follower", "creation", "event", "movement"
    let promptTemplate: String    // Prompt text with {subject}, {place}, {year} placeholders
    let location: String
    let year: Int
    let subject: String?          // nil for "subject" question type, filled for entity questions

    /// Fill placeholders with actual values.
    func filledPrompt() -> String {
        promptTemplate
            .replacingOccurrences(of: "{subject}", with: subject ?? "UNKNOWN")
            .replacingOccurrences(of: "{place}", with: location)
            .replacingOccurrences(of: "{year}", with: String(year))
    }
}

struct PromptTestResult: Sendable {
    let testCase: PromptTestCase
    let fmAnswer: String?         // nil = refusal/error
    let error: String?            // error description if failed
    let latencyMs: Int
}

struct ProposedRewrite: Sendable {
    let questionType: String
    let template: String
    let rationale: String
    let testAgainst: [LocationYear]
}

struct RoundResult: Sendable {
    let roundNumber: Int
    let results: [PromptTestResult]
    let claudeEvaluation: String  // Claude's full analysis text
    let proposedRewrites: [ProposedRewrite]
}

// MARK: - Harness Error

enum HarnessError: Error, CustomStringConvertible {
    case noApiKey
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case parseError

    var description: String {
        switch self {
        case .noApiKey: return "No CLAUDE_API_KEY found in Info.plist"
        case .invalidResponse: return "Invalid HTTP response"
        case .apiError(let code, let body): return "API error \(code): \(body)"
        case .parseError: return "Failed to parse Claude response"
        }
    }
}

// MARK: - Claude Evaluator

actor ClaudeEvaluator {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let model = "claude-sonnet-4-20250514"

    nonisolated private var apiKey: String? {
        Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
    }

    /// Send a system + user message to Claude and return the text response.
    func evaluate(system: String, user: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw HarnessError.noApiKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HarnessError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw HarnessError.apiError(statusCode: httpResponse.statusCode, body: responseBody)
        }

        // Parse Anthropic response: { "content": [{ "type": "text", "text": "..." }] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw HarnessError.parseError
        }

        return text
    }
}

// MARK: - Seed Data

struct HarnessSeedData {
    /// 20 locations spanning major cities, smaller cities, and international
    static let locations = [
        // Major US cities
        "New York City", "Los Angeles", "Chicago",
        // Medium US cities
        "San Francisco", "Detroit", "Nashville", "New Orleans", "Seattle", "Austin", "Memphis",
        // Smaller / harder US cities
        "Kansas City", "Minneapolis", "Portland",
        // International major
        "London", "Tokyo", "Lagos", "Berlin", "Paris",
        // International smaller
        "Kingston", "Havana"
    ]

    /// 10 years spanning 1926-2026
    static let years = [1932, 1947, 1955, 1965, 1973, 1977, 1984, 1992, 2005, 2020]

    /// Seed location/year combos for the first round (5 diverse pairs)
    static let seedCombos: [LocationYear] = [
        LocationYear(location: "London", year: 1977),
        LocationYear(location: "Detroit", year: 1965),
        LocationYear(location: "San Francisco", year: 1984),
        LocationYear(location: "Kansas City", year: 1955),
        LocationYear(location: "Lagos", year: 1973),
    ]

    /// Current prompt templates -- the baseline we're optimizing from.
    /// Keyed by question type. Use {subject}, {place}, {year} placeholders.
    static let baselineTemplates: [(questionType: String, template: String)] = [
        ("subject", "Which music artist FROM {place} was most popular in {year}? Answer with just the name."),
        ("influence", "{subject}'s biggest musical influence? Answer with ONLY the name."),
        ("peer", "A musical peer of {subject} in {place} around {year}? Answer with ONLY the name."),
        ("follower", "An artist most directly influenced by {subject}? Answer with ONLY the name."),
        ("event", "A major music event in {place} around {year} connected to {subject}? Answer with ONLY the event name."),
        ("creation", "{subject}'s most famous song or album around {year}? Answer with ONLY the title."),
        ("movement", "The music genre or movement {subject} was part of in {year}? Answer with ONLY the genre name."),
    ]
}

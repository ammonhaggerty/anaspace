import Foundation

// MARK: - Claude Model

/// Model tier for Claude API calls
enum ClaudeModel: String, Sendable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-5-20250929"
}

// MARK: - Assembly Path

/// Determines which user message template to use based on available signals.
enum AssemblyPath: String, Sendable {
    case musicOnly          // Observe tap, Shazam match, no transcript
    case musicPlusCommand   // Hold with Shazam + transcript
    case voiceCommand       // Hold, no Shazam, short transcript (<=20 words)
    case lyricIdentification // Hold, no Shazam, long transcript (>20 words)
    case locationOnly       // Silent observation, no audio signals
}

// MARK: - Culture Map Response (Legacy)

struct CultureMapResponse: Sendable {
    let subject: String
    let subjectType: String
    let place: String
    let year: Int
    let narrative: String
    let connections: [CultureConnection]
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

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a cultural context engine for a music/culture discovery app. Your job is to build \
    a "culture map" anchored to a Triad: Subject + Place + Year.

    ## The Triad
    - **Subject**: Always resolves to an artist or band name (never a song or album title).
    - **Place**: A geographic location (city, region, or country).
    - **Year**: A specific year that anchors the cultural moment.

    Every entity you return must connect to at least 2 of the 3 triad dimensions. Allow slight \
    flexibility: +/-2 years on time, same metro area on location.

    ## Entity Types
    Each entity has one of these types:
    - collaborator: Worked directly with the subject
    - peer: Active in the same scene/era but independent
    - influence: Inspired or preceded the subject
    - follower: Influenced by or succeeded the subject
    - creation: Songs, albums, or artistic works
    - place: Venues, studios, landmarks
    - event: Historical or cultural events
    - movement: Genres, cultural movements, scenes

    ## Output Format
    Return ONLY a JSON object (no markdown fences, no commentary):
    {
      "subject": "ARTIST NAME",
      "subjectType": "artist|band|poet|composer|dj|producer",
      "birthInfo": "B. YEAR, PLACE" or "EST. YEAR, PLACE" for groups,
      "place": "City, State | Country",
      "year": 1978,
      "bio": "Two paragraphs, 600-800 characters total. First paragraph: what the subject was doing in this specific year. Second paragraph: the subject's connection to this specific place.",
      "narrative": "One sentence connecting subject, place, and year.",
      "entities": [
        {
          "name": "ENTITY NAME",
          "subtitle": "Optional short context (album name, venue nickname, etc.)" or null,
          "entityType": "collaborator|peer|influence|follower|creation|place|event|movement",
          "relationship": "Brief description of connection to subject",
          "relevance": 0.95
        }
      ]
    }

    ## Rules
    - Return 1-12 entities. Quality over quantity.
    - Entity names: prefer 14 characters or fewer, 20 max. Use ALL CAPS.
    - Relevance: 0.0-1.0. Reserve 0.9+ for direct collaborators or defining works.
    - Bio: Do NOT write a generic biography. Ground it in the specific year and place.
    - Subject: Always resolve to the primary artist/band, never a song or album title.
    - birthInfo: Use "B. YEAR, PLACE" for individuals, "EST. YEAR, PLACE" for groups/bands.
    - Subtitles: Just the title itself (e.g. "Illmatic", "Abbey Road"). No format descriptors \
    (no "Double Album", "LP", "Single", "Debut", etc.). Use for creation entities and place nicknames, or null.
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

        let text = extractResponseText(from: json)
        print("[Claude] Response: \(text)")
        return parseClaudeResponse(text)
    }

    // MARK: - Assembly Path Detection

    private func detectPath(from signals: ObservationSignals) -> AssemblyPath {
        let hasShazam = signals.shazamResult != nil
        let hasTranscript = signals.transcript.map { !$0.text.isEmpty } ?? false
        let wordCount = signals.transcript?.wordCount ?? 0

        switch (hasShazam, hasTranscript) {
        case (true, true):
            return .musicPlusCommand
        case (true, false):
            return .musicOnly
        case (false, true):
            return wordCount <= 20 ? .voiceCommand : .lyricIdentification
        case (false, false):
            return .locationOnly
        }
    }

    // MARK: - User Message Construction

    private func buildUserMessage(from signals: ObservationSignals) -> String {
        let path = detectPath(from: signals)
        let location = signals.location.map { LocationService.displayLabel(for: $0) } ?? "unknown location"
        let currentYear = Calendar.current.component(.year, from: .now)

        switch path {
        case .musicOnly:
            return buildMusicOnlyMessage(signals: signals, location: location)

        case .musicPlusCommand:
            return buildMusicPlusCommandMessage(signals: signals, location: location)

        case .voiceCommand:
            return buildVoiceCommandMessage(signals: signals, location: location, currentYear: currentYear)

        case .lyricIdentification:
            return buildLyricIdentificationMessage(signals: signals, location: location)

        case .locationOnly:
            return buildLocationOnlyMessage(location: location, currentYear: currentYear)
        }
    }

    private func buildMusicOnlyMessage(signals: ObservationSignals, location: String) -> String {
        guard let shazam = signals.shazamResult else { return "" }
        var lines = [
            "OBSERVATION: Music identified",
            "Song: \(shazam.title) | Artist: \(shazam.artist)"
        ]
        if let album = shazam.album { lines[1] += " | Album: \(album)" }
        if let year = shazam.releaseYear { lines[1] += " | Year: \(year)" }
        if !shazam.genres.isEmpty { lines[1] += " | Genres: \(shazam.genres.joined(separator: ", "))" }
        lines.append("Location: \(location)")
        lines.append("")
        lines.append("Build the culture map. Subject = artist, Year = release year, Place = user's location.")
        return lines.joined(separator: "\n")
    }

    private func buildMusicPlusCommandMessage(signals: ObservationSignals, location: String) -> String {
        guard let shazam = signals.shazamResult,
              let transcript = signals.transcript else { return "" }
        var songLine = "Song: \(shazam.title) | Artist: \(shazam.artist)"
        if let year = shazam.releaseYear { songLine += " | Year: \(year)" }
        return """
        OBSERVATION: Music + user speech
        \(songLine)
        Location: \(location)
        User said: "\(transcript.text)"

        Song sets initial triad. User speech may override dimensions or ask a question. Parse intent.
        """
    }

    private func buildVoiceCommandMessage(signals: ObservationSignals, location: String, currentYear: Int) -> String {
        guard let transcript = signals.transcript else { return "" }
        return """
        OBSERVATION: Voice command (no music)
        User said: "\(transcript.text)"
        Location: \(location) | Current year: \(currentYear)

        Parse for subject, place, year. Unspecified dimensions use defaults. Build culture map.
        """
    }

    private func buildLyricIdentificationMessage(signals: ObservationSignals, location: String) -> String {
        guard let transcript = signals.transcript else { return "" }
        return """
        OBSERVATION: Possible lyrics (no Shazam match)
        User sang/recited: "\(transcript.text)"
        Location: \(location)

        Identify the song and artist. Subject = that artist, Year = song's release year.
        If unidentifiable, fall back to most notable artist for this location.
        """
    }

    private func buildLocationOnlyMessage(location: String, currentYear: Int) -> String {
        return """
        OBSERVATION: Silent (no audio signals)
        Location: \(location) | Year: \(currentYear)

        The year anchor is \(currentYear) — do NOT pick a historical year. Find the most culturally \
        relevant musician connected to this location RIGHT NOW (active, touring, releasing music, or \
        culturally resonant in \(currentYear)). Subject = that artist, Year = \(currentYear), Place = location.
        Search: neighborhood -> city -> metro area -> region.
        """
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
            "max_tokens": 2048,
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

    /// Strip markdown code fences if present, then parse JSON.
    private func stripCodeFences(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseClaudeResponse(_ text: String) -> ClaudeResult {
        let cleaned = stripCodeFences(text)

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ClaudeResult(
                subject: json["subject"] as? String ?? "Unknown",
                subjectType: json["subjectType"] as? String ?? "unknown",
                birthInfo: json["birthInfo"] as? String ?? "",
                place: json["place"] as? String ?? "Unknown",
                year: json["year"] as? Int ?? Calendar.current.component(.year, from: .now),
                bio: json["bio"] as? String ?? "",
                narrative: json["narrative"] as? String ?? text,
                connections: parseEntities(json["entities"]),
                isStreaming: false
            )
        }

        // Fallback: treat the entire text as narrative
        return ClaudeResult(
            subject: "Observation",
            subjectType: "unknown",
            birthInfo: "",
            place: "Unknown",
            year: Calendar.current.component(.year, from: .now),
            bio: "",
            narrative: text,
            connections: [],
            isStreaming: false
        )
    }

    private func parseEntities(_ raw: Any?) -> [CultureConnection] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let name = item["name"] as? String,
                  let relationship = item["relationship"] as? String else { return nil }
            // Strip to first line only (drop format descriptors like "Double Album")
            let subtitle = (item["subtitle"] as? String)?
                .components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespaces)
            let entityType = (item["entityType"] as? String)
                .flatMap { EntityType(rawValue: $0) } ?? .peer
            let relevance = item["relevance"] as? Double ?? 0.5
            return CultureConnection(
                name: name,
                subtitle: subtitle,
                entityType: entityType,
                relationship: relationship,
                relevance: relevance
            )
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

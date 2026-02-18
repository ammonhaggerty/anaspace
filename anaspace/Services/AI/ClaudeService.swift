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
    private let model = ClaudeModel.haiku

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
      "bio": "Two short paragraphs, 400-500 characters total. First paragraph: what the subject was doing in this specific year. Second paragraph: the subject's connection to this specific place.",
      "narrative": "One sentence connecting subject, place, and year.",
      "entities": [
        {
          "name": "SHORT NAME (max 14 chars, 20 absolute max). ALL CAPS. Proper noun only — no locations, descriptors, or subtitles. e.g. BLACK PANTHERS not BLACK PANTHER PARTY OAKLAND HQ.",
          "subtitle": "Optional short context" or null,
          "entityType": "collaborator|peer|influence|follower|creation|place|event|movement",
          "relationship": "Brief description of connection to subject",
          "relevance": 0.95,
          "description": "400-500 characters. How this entity connects to the subject in the stated year and place. Ground it specifically — not a generic bio of the entity.",
          "recommendedSong": "Song Title" or null
        }
      ]
    }

    ## Rules
    - Return 1-10 entities. Quality over quantity.
    - Entity names MUST be the shortest recognizable proper noun. HARD LIMIT: 20 characters max, \
    target 14 or fewer. ALL CAPS. Strip everything that isn't the core name: \
    no locations, no "HQ"/"Studios"/"Party"/"Festival", no descriptors, no subtitles. \
    Put context in "subtitle" or "description" instead. \
    RIGHT: "BLACK PANTHERS", "MUSCLE SHOALS", "ABBEY ROAD", "FILLMORE", "MONTEREY POP" \
    WRONG: "BLACK PANTHER PARTY OAKLAND HQ", "MUSCLE SHOALS SOUND STUDIO", "ABBEY ROAD STUDIOS LONDON", \
    "FILLMORE WEST VENUE", "MONTEREY POP FESTIVAL 1967"
    - Relevance: 0.0-1.0. Reserve 0.9+ for direct collaborators or defining works.
    - Bio: 400-500 characters max. Do NOT write a generic biography. Ground it in the specific year and place.
    - Entity descriptions: 400-500 characters. Explain this entity's specific connection to the subject \
    in the stated year and place. Not a generic summary of the entity.
    - Subject: Always resolve to the primary artist/band, never a song or album title.
    - birthInfo: Use "B. YEAR, PLACE" for individuals, "EST. YEAR, PLACE" for groups/bands.
    - recommendedSong: For artist entities (collaborator, peer, influence, follower), pick the one song \
    that best represents this connection to the subject in the stated year. Prefer: a collaboration between \
    subject and entity, a song from the entity's album closest to the year, or the entity's most iconic song \
    from that era. For non-artist entities (creation, place, event, movement), set to null. \
    Use the standard song title — no "(feat. ...)" suffixes or remaster labels.
    - Subtitles: Use null unless there's a genuinely useful distinguishing detail. \
    For creation entities, subtitle is ALWAYS null — the name IS the title. \
    For non-creation entities, subtitle can be a short distinguishing note (e.g. a venue's \
    well-known nickname, a person's instrument). \
    NEVER use generic category labels as subtitles: no "Concert Venue", "Recording Studio", \
    "Music Festival", "Record Label", "Cultural Movement", "Nightclub", etc. The entityType \
    already conveys the category — subtitle must add specific context or be null. \
    Never include album names alongside song names or vice versa. Pick one creation per work. \
    No format descriptors (no "Double Album", "LP", "Single", "Debut", etc.).
    - CRITICAL: You must ALWAYS return the JSON object. Never return commentary, apologies, \
    explanations, or questions. If you lack specific knowledge about a place or era, broaden \
    your search (city → region → country) until you find a relevant artist. There is always \
    a culturally relevant musician for any location and year — find one.
    """

    // MARK: - ObservationService Conformance

    func activate() async throws {
        apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        isAvailable = apiKey != nil && apiKey?.isEmpty == false
    }

    func deactivate() {}

    // MARK: - Public API

    /// Query Claude with year and location fixed, finding the closest match to a subject's legacy.
    func processYearChange(subject: String, year: Int, location: String) async throws -> ClaudeResult {
        let userMessage = """
        YEAR CHANGE: The user was exploring \(subject) and changed the year to \(year).
        Location: \(location)

        Year \(year) and location are FIXED — do not change them. Find the artist or musician \
        most connected to \(subject)'s musical legacy, lineage, or spirit who was active in \
        \(location) in \(year). This could be a direct collaborator, a successor carrying their \
        influence, or an artist who embodies a similar cultural role in that era and place. \
        The subject should NOT be \(subject) themselves unless they were genuinely active there in \(year). \
        You MUST return the JSON object. Never return commentary, apologies, or explanations. \
        There is always a relevant artist — broaden your search until you find one. \
        Build the culture map around this new subject, anchored to \(year) and \(location).
        """
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

    /// Query Claude with location change — subject and year are fixed, location is new.
    /// Encourages finding a local equivalent artist over showing the same artist in the new place.
    func processLocationChange(subject: String, year: Int, location: String) async throws -> ClaudeResult {
        let userMessage = """
        LOCATION CHANGE: The user was exploring \(subject) in \(year) and moved to \(location).
        Subject: \(subject) | Year: \(year) | New location: \(location)

        Year \(year) is FIXED — do not change it. The new location \(location) is FIXED. \
        Your primary goal: find the LOCAL artist or musician in \(location) who best represents \
        the musical lineage, spirit, or cultural role of \(subject) in \(year). \
        STRONGLY prefer a local artist — someone who was born in, based in, or primarily associated \
        with \(location). A local equivalent is almost always more interesting than showing \(subject) \
        in a new city. \
        Only keep \(subject) as the subject if they have a genuine, specific connection to \(location) \
        in \(year) (e.g., they lived there, recorded there, performed a landmark show there). \
        A generic "their music was popular worldwide" is NOT a sufficient connection. \
        Search broadly: neighborhood → city → region → country. If no exact city match exists, \
        find the best artist from the surrounding region or country for that era. \
        You MUST return the JSON object. Never return commentary, apologies, or explanations. \
        There is always a relevant artist — broaden your search until you find one. \
        Build the culture map around this subject, anchored to \(year) and \(location).
        """
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

    /// Query Claude with a subject change — location is fixed, year flexes to most relevant era.
    func processSubjectChange(newSubject: String, priorSubject: String, location: String) async throws -> ClaudeResult {
        let userMessage = """
        SUBJECT CHANGE: The user was exploring \(priorSubject) in \(location) and shifted focus to \(newSubject).
        New subject: \(newSubject) | Location: \(location)

        Location \(location) is FIXED — do not change it. \
        The year should be the era when \(newSubject) was most culturally influential or relevant \
        to \(location). Let the year gravitate to the peak of their impact on this place. \
        Build the culture map around \(newSubject), showing their connections, influences, peers, \
        and followers — with emphasis on artists and cultural figures tied to \(location). \
        Include the prior subject \(priorSubject) as a connection if there is a genuine relationship. \
        You MUST return the JSON object. Never return commentary, apologies, or explanations. \
        There is always a relevant cultural map — broaden your search until you find one.
        """
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

    /// Send a shortcut query with a pre-built prompt directly to Claude.
    func processShortcutQuery(prompt: String) async throws -> ClaudeResult {
        print("[Claude] Shortcut request: \(prompt)")

        let request = try buildRequest(userMessage: prompt)
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
            "max_tokens": 4096,
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
        // Log stop reason — "max_tokens" means truncation
        if let stopReason = json["stop_reason"] as? String {
            print("[Claude] stop_reason: \(stopReason)")
            if stopReason == "max_tokens" {
                print("[Claude] WARNING: Response was truncated (hit max_tokens limit)")
            }
        }

        guard let content = json["content"] as? [[String: Any]] else {
            print("[Claude] EXTRACT FAIL: no 'content' array in response. Keys: \(json.keys.sorted())")
            if let errorMsg = json["error"] as? [String: Any] {
                print("[Claude] API error object: \(errorMsg)")
            }
            return ""
        }
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        if text.isEmpty {
            print("[Claude] EXTRACT WARN: content blocks present but no text extracted. Blocks: \(content.count)")
        }
        return text
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

        guard let data = cleaned.data(using: .utf8) else {
            print("[Claude] PARSE FAIL: could not convert to UTF-8 data")
            print("[Claude] Raw text (\(text.count) chars): \(text.prefix(500))")
            return fallbackResult(text)
        }

        // Try parsing as-is first
        if let json = tryParseJSON(data) {
            return buildResult(from: json, rawText: text)
        }

        // Attempt to repair truncated JSON
        print("[Claude] Initial parse failed, attempting JSON repair (\(cleaned.count) chars)")
        if let repaired = repairTruncatedJSON(cleaned),
           let repairedData = repaired.data(using: .utf8),
           let json = tryParseJSON(repairedData) {
            print("[Claude] JSON repair succeeded")
            return buildResult(from: json, rawText: text)
        }

        print("[Claude] PARSE FAIL: JSON repair also failed")
        print("[Claude] Cleaned text (\(cleaned.count) chars): \(cleaned.prefix(500))")
        return fallbackResult(text)
    }

    private func tryParseJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func buildResult(from json: [String: Any], rawText: String) -> ClaudeResult {
        let result = ClaudeResult(
            subject: json["subject"] as? String ?? "Unknown",
            subjectType: json["subjectType"] as? String ?? "unknown",
            birthInfo: json["birthInfo"] as? String ?? "",
            place: json["place"] as? String ?? "Unknown",
            year: json["year"] as? Int ?? Calendar.current.component(.year, from: .now),
            bio: json["bio"] as? String ?? "",
            narrative: json["narrative"] as? String ?? rawText,
            connections: parseEntities(json["entities"]),
            isStreaming: false
        )
        print("[Claude] Parsed OK: subject=\(result.subject), place=\(result.place), year=\(result.year), entities=\(result.connections.count)")
        return result
    }

    /// Attempt to repair truncated JSON by closing open strings, arrays, and objects.
    /// Uses two strategies: first tries closing at the truncation point, then falls back
    /// to trimming the last incomplete entry.
    private func repairTruncatedJSON(_ text: String) -> String? {
        // Strategy 1: close at truncation point
        if let result = attemptJSONClose(text) { return result }

        // Strategy 2: drop back to the last complete entry in the innermost container
        let trimmed = trimToLastCompleteEntry(text)
        if trimmed != text, let result = attemptJSONClose(trimmed) { return result }

        return nil
    }

    /// Close any open strings, trim trailing separators, and append missing brackets/braces.
    private func attemptJSONClose(_ text: String) -> String? {
        var repaired = text

        // Close any open string
        var inString = false
        var escaped = false
        for ch in repaired {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { inString.toggle() }
        }
        if inString { repaired += "\"" }

        // Trim trailing comma, colon, or whitespace outside strings
        while let last = repaired.last, ",: \t\n\r".contains(last) {
            repaired = String(repaired.dropLast())
        }

        // Count unclosed braces/brackets
        var braces = 0, brackets = 0
        inString = false; escaped = false
        for ch in repaired {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            switch ch {
            case "{": braces += 1
            case "}": braces -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            default: break
            }
        }

        for _ in 0..<max(0, brackets) { repaired += "]" }
        for _ in 0..<max(0, braces) { repaired += "}" }

        // Verify it actually parses
        guard let data = repaired.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return repaired
    }

    /// Trim back to the last `}`, `]`, or complete value before the truncation.
    /// This drops an incomplete entity/entry at the end.
    private func trimToLastCompleteEntry(_ text: String) -> String {
        // Find the last `}` or `]` that isn't inside a string
        var lastCloseIndex: String.Index?
        var inString = false
        var escaped = false
        for i in text.indices {
            let ch = text[i]
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            guard !inString else { continue }
            if ch == "}" || ch == "]" {
                lastCloseIndex = i
            }
        }
        guard let idx = lastCloseIndex else { return text }
        return String(text[...idx])
    }

    private func fallbackResult(_ text: String) -> ClaudeResult {
        ClaudeResult(
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

    /// Strip content after the first newline (real or literal "\n") and trim whitespace.
    private func firstLine(_ value: String?) -> String? {
        guard var text = value, !text.isEmpty else { return nil }
        // Handle literal two-character "\n" sequences (in case model emits them)
        if let range = text.range(of: "\\n") {
            text = String(text[..<range.lowerBound])
        }
        let line = text.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces)
        return (line?.isEmpty == true) ? nil : line
    }

    private func parseEntities(_ raw: Any?) -> [CultureConnection] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let rawName = item["name"] as? String,
                  let relationship = item["relationship"] as? String else { return nil }
            let name = firstLine(rawName) ?? rawName
            let subtitle = firstLine(item["subtitle"] as? String)
            let entityType = (item["entityType"] as? String)
                .flatMap { EntityType(rawValue: $0) } ?? .peer
            let relevance = item["relevance"] as? Double ?? 0.5
            let description = item["description"] as? String ?? ""
            let recommendedSong = firstLine(item["recommendedSong"] as? String)
            return CultureConnection(
                name: name,
                subtitle: subtitle,
                entityType: entityType,
                relationship: relationship,
                relevance: relevance,
                description: description,
                recommendedSong: recommendedSong
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

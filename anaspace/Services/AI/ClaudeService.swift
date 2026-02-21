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
    - **Subject**: Usually an artist or band name. However, when the user explicitly focuses on a \
    non-artist entity (a creation, place, event, or movement), the subject IS that entity. \
    In that case, subjectType should be the entity type (e.g. "album", "venue", "festival", "genre") \
    and the entities should be the people, bands, works, and cultural forces that define it.
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
      "subject": "SUBJECT NAME",
      "subjectType": "artist|band|poet|composer|dj|producer|album|song|venue|studio|festival|genre|movement|event",
      "birthInfo": "B. YEAR, PLACE" for individuals, "EST. YEAR, PLACE" for groups, or "YEAR, PLACE" for non-artist subjects (e.g. album release year/city, venue opening year/city),
      "place": "City, State | Country",
      "year": 1978,
      "bio": "Two short paragraphs, 300-400 characters total. First paragraph: what the subject was doing in this specific year. Second paragraph: the subject's connection to this specific place.",
      "narrative": "One sentence connecting subject, place, and year.",
      "entities": [
        {
          "name": "SHORT NAME (max 14 chars, 20 absolute max). ALL CAPS. Proper noun only — no locations, descriptors, or subtitles. e.g. BLACK PANTHERS not BLACK PANTHER PARTY OAKLAND HQ.",
          "subtitle": "Optional short context" or null,
          "entityType": "collaborator|peer|influence|follower|creation|place|event|movement",
          "relationship": "Brief description of connection to subject",
          "relevance": 0.95,
          "recommendedSong": "Song Title" or null
        }
      ],
      "keyArtists": ["ARTIST 1", "ARTIST 2", "ARTIST 3", "ARTIST 4", "ARTIST 5"],
      "entityDescriptions": [
        {
          "name": "ENTITY NAME (matching name from entities array)",
          "description": "200-300 characters. How this entity connects to the subject in the stated year and place. Ground it specifically — not a generic bio of the entity."
        }
      ]
    }

    ## Rules
    - keyArtists: For non-artist subjects (albums, venues, events, movements, genres), list the \
    top 5 artists/bands most associated with this subject, ordered by relevance. These are used \
    for music playback — the app will search each artist's catalog near the stated year. \
    For artist subjects, set keyArtists to an empty array [].
    - Return 8 entities. Fill the culture map — more connections paint a richer picture.
    - Entity names MUST be the shortest recognizable proper noun. HARD LIMIT: 20 characters max, \
    target 14 or fewer. ALL CAPS. Strip everything that isn't the core name: \
    no locations, no "HQ"/"Studios"/"Party"/"Festival", no descriptors, no subtitles. \
    Put context in "subtitle" or "description" instead. \
    RIGHT: "BLACK PANTHERS", "MUSCLE SHOALS", "ABBEY ROAD", "FILLMORE", "MONTEREY POP" \
    WRONG: "BLACK PANTHER PARTY OAKLAND HQ", "MUSCLE SHOALS SOUND STUDIO", "ABBEY ROAD STUDIOS LONDON", \
    "FILLMORE WEST VENUE", "MONTEREY POP FESTIVAL 1967"
    - Relevance: 0.0-1.0. Reserve 0.9+ for direct collaborators or defining works.
    - Bio: 300-400 characters max. Do NOT write a generic biography. Ground it in the specific year and place.
    - Entity descriptions: 200-300 characters. Explain this entity's specific connection to the subject \
    in the stated year and place. Not a generic summary of the entity.
    - Subject: By default, resolve to the primary artist/band. Exception: when the user message \
    explicitly states a non-artist focus (e.g. "FOCUS ON: album/venue/movement"), keep that entity \
    as the subject and populate entities with the artists, works, and forces that define it.
    - birthInfo: Use "B. YEAR, PLACE" for individuals, "EST. YEAR, PLACE" for groups/bands, \
    or "YEAR, PLACE" for non-artist subjects (release year, opening year, founding year, etc.).
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
    - LOCATION CHANGES — GEOGRAPHIC ANCHOR IS MANDATORY: When the user message says \
    "LOCATION CHANGE", the new subject MUST be from, founded in, or synonymous with the NEW \
    location. Never carry over a subject from the previous location. A strong musical connection \
    to the prior subject does NOT justify picking something from the wrong city or country. \
    Geography comes first, musical spirit second.
    - CRITICAL: You must ALWAYS return the JSON object. Never return commentary, apologies, \
    explanations, or questions. If you lack specific knowledge about a place or era, broaden \
    your search (city → region → country) until you find a relevant subject. There is always \
    a culturally relevant subject for any location and year — find one.
    """

    // MARK: - ObservationService Conformance

    func activate() async throws {
        apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        isAvailable = apiKey != nil && apiKey?.isEmpty == false
    }

    func deactivate() {}

    // MARK: - Public API

    /// Query Claude with year and location fixed, finding the closest match to a subject's legacy.
    func processYearChange(
        subject: String, year: Int, location: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
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

        let request = try buildStreamingRequest(userMessage: userMessage)
        return try await streamRequest(request, onUpdate: onUpdate)
    }

    /// Query Claude with location change — subject and year are fixed, location is new.
    /// Finds the local equivalent that matches the current subject's type and musical spirit.
    func processLocationChange(
        subject: String, subjectType: String, year: Int, location: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let isArtistType = ["artist", "band", "poet", "composer", "dj", "producer"].contains(subjectType.lowercased())
        let typeGuidance: String
        if isArtistType {
            typeGuidance = """
            The current subject is an artist/band. Find the LOCAL artist or musician in \(location) \
            who best embodies the same musical spirit, ethos, or genre as \(subject) in \(year).
            """
        } else {
            typeGuidance = """
            The current subject is a \(subjectType). FIRST, try to find a similar \(subjectType) in \
            \(location) that embodies the same musical spirit, ethos, or genre as \(subject). \
            Keep likes with likes: if the subject is an event, find a comparable event; if it's a \
            venue, find a comparable venue; if it's a movement, find the local equivalent movement. \
            The replacement should be FROM \(location) or closely associated with \(location). \
            If no suitable \(subjectType) exists in \(location) for \(year), THEN fall back to finding \
            a local artist or band that embodies the same musical spirit as \(subject).
            """
        }

        let userMessage = """
        LOCATION CHANGE: The user was exploring \(subject) (\(subjectType)) in \(year) and moved to \(location).
        Subject: \(subject) | Subject type: \(subjectType) | Year: \(year) | New location: \(location)

        Year \(year) is FIXED — do not change it. The new location \(location) is FIXED.

        Think of this as: "Who is \(subject)'s closest counterpart in \(location) in \(year)?"

        ## RULE 1: CLOSEST ANALOG TO \(subject)
        The new subject must be the strongest musical analog to \(subject) — someone (or something) \
        with a direct connection: similar style, energy, genre, collaboration, shared lineage, or \
        mutual influence. The tighter the musical relationship to \(subject), the better. \
        An obscure but deeply connected choice is better than a famous but loosely related one.

        \(typeGuidance)

        ## RULE 2: MUST BE FROM \(location)
        The new subject MUST also be closely associated with \(location) — born there, based there, \
        or synonymous with it. Do NOT pick a subject from another city or country, no matter how \
        strong the musical link to \(subject). If \(subject) themselves have a genuine, specific \
        connection to \(location) in \(year) (lived there, recorded there, performed a landmark show), \
        they can remain the subject — but "popular worldwide" is NOT enough. \
        Search broadly if needed: neighborhood → city → region → country.

        ## ENTITY RULES FOR LOCATION CHANGES
        The culture map should reflect the new subject's world anchored to \(location):
        - **influence**: Can be from anywhere — who shaped the subject's sound.
        - **peer**: Strongly prefer local to \(location) — who was part of the same scene HERE?
        - **follower**: Strongly prefer local to \(location) — who here carried on this tradition?
        - **collaborator**: Strongly prefer connections to \(location) — sessions, tours, or projects here.
        - **creation, place, event, movement**: Should be tied to \(location).
        Aim for 8 entities. A rich, full culture map is always better than a sparse one.

        You MUST return the JSON object. Never return commentary, apologies, or explanations. \
        There is always a relevant subject — broaden your search until you find one. \
        Build the culture map around this subject, anchored to \(year) and \(location).
        """
        print("[Claude] *** LOCATION CHANGE PATH *** subjectType=\(subjectType) subject=\(subject) location=\(location)")
        print("[Claude] Request: \(userMessage)")

        let request = try buildStreamingRequest(userMessage: userMessage)
        return try await streamRequest(request, onUpdate: onUpdate)
    }

    /// Query Claude with a subject change — location is fixed, year flexes to most relevant era.
    func processSubjectChange(
        connection: CultureConnection? = nil, newSubject: String, priorSubject: String,
        location: String, year: Int,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        // Build entity context string for non-artist entities
        let entityContext: String
        if let conn = connection, !conn.entityType.hasArtistCatalog {
            var parts = ["\(newSubject) is a \(conn.entityType.rawValue)"]
            if let subtitle = conn.subtitle { parts.append("(\(subtitle))") }
            parts.append("connected to \(priorSubject) in \(location) circa \(year)")
            parts.append("— \(conn.relationship)")
            parts.append("Context: \(conn.description)")
            entityContext = parts.joined(separator: " ")
        } else {
            entityContext = "\(newSubject) (artist/band)"
        }

        let isArtist = connection?.entityType.hasArtistCatalog ?? true
        let entityType = connection?.entityType.rawValue ?? "entity"
        let subjectGuidance: String
        if isArtist {
            subjectGuidance = """
            Build the culture map around \(newSubject), showing their connections, influences, peers, \
            and followers — with emphasis on artists and cultural figures tied to \(location).
            """
        } else {
            subjectGuidance = """
            FOCUS ON NON-ARTIST ENTITY: \(newSubject) is a \(entityType). Keep \(newSubject) as the \
            subject — do NOT resolve it to an artist. Set subjectType to "\(entityType)". \
            The entities should be the people, bands, songs, movements, places, and cultural forces \
            that define \(newSubject). Prioritize artist entities (collaborators, peers, influences) so \
            the culture map is rich with musicians — these are the people who made \(newSubject) what it is. \
            Include the prior subject \(priorSubject) as a high-relevance connection. \
            For recommendedSong on artist entities: pick the song that best connects that artist to \(newSubject). \
            The bio should describe what \(newSubject) is, its significance in \(location), and why it matters \
            in the context of the stated year.
            """
        }

        let userMessage = """
        SUBJECT CHANGE: The user was exploring \(priorSubject) in \(location) (\(year)) and shifted focus to: \(entityContext).
        Location: \(location) | Prior year: \(year)

        Location \(location) is FIXED — do not change it. \
        \(subjectGuidance) \
        The year should be the era when this subject was most culturally influential or relevant \
        to \(location). Let the year gravitate to the peak of their impact on this place. \
        Include the prior subject \(priorSubject) as a connection if there is a genuine relationship. \
        You MUST return the JSON object. Never return commentary, apologies, or explanations. \
        There is always a relevant cultural map — broaden your search until you find one.
        """
        print("[Claude] Request: \(userMessage)")

        let request = try buildStreamingRequest(userMessage: userMessage)
        return try await streamRequest(request, onUpdate: onUpdate)
    }

    /// Send a shortcut query with a pre-built prompt directly to Claude.
    func processShortcutQuery(
        prompt: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        print("[Claude] Shortcut request: \(prompt)")

        let request = try buildStreamingRequest(userMessage: prompt)
        return try await streamRequest(request, onUpdate: onUpdate)
    }

    /// Send observation signals to Claude and return a single result.
    func processObservation(
        from signals: ObservationSignals,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let userMessage = buildUserMessage(from: signals)
        print("[Claude] Request: \(userMessage)")

        let request = try buildStreamingRequest(userMessage: userMessage)
        return try await streamRequest(request, onUpdate: onUpdate)
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

        if signals.hasActiveTriad,
           let subject = signals.activeSubject,
           let activeYear = signals.activeYear,
           let loc = signals.activeLocationLabel {
            return """
            OBSERVATION: Music + user speech
            \(songLine)
            GPS Location: \(location)
            User said: "\(transcript.text)"

            ACTIVE CONTEXT: Subject: \(subject) | Year: \(activeYear) | Location: \(loc)

            The detected song provides context. The user's speech may override triad dimensions. \
            Interpret their intent in the context of the existing triad — preserve any dimensions \
            they don't explicitly change.
            """
        }

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

        if signals.hasActiveTriad,
           let subject = signals.activeSubject,
           let year = signals.activeYear,
           let loc = signals.activeLocationLabel {
            return """
            OBSERVATION: Voice command (no music)
            User said: "\(transcript.text)"
            GPS Location: \(location)

            ACTIVE CONTEXT — the user already has a culture map loaded:
            Subject: \(subject) | Year: \(year) | Location: \(loc)

            Interpret the user's speech in the context of this existing triad. \
            If they mention a year (e.g. "how about 1982"), change the year but KEEP the subject and location. \
            If they mention an artist, band, song, or lyrics, resolve it as a subject change — \
            keep the location and let the year flex to the most relevant era. \
            If they mention a place, treat it as a location change — keep the subject and year. \
            Only dimensions they explicitly reference should change; preserve the rest. \
            Build the culture map with the updated triad.
            """
        }

        return """
        OBSERVATION: Voice command (no music)
        User said: "\(transcript.text)"
        Location: \(location) | Current year: \(currentYear)

        Parse for subject, place, year. Unspecified dimensions use defaults. Build culture map.
        """
    }

    private func buildLyricIdentificationMessage(signals: ObservationSignals, location: String) -> String {
        guard let transcript = signals.transcript else { return "" }

        if signals.hasActiveTriad,
           let subject = signals.activeSubject,
           let year = signals.activeYear,
           let loc = signals.activeLocationLabel {
            return """
            OBSERVATION: Possible lyrics (no Shazam match)
            User sang/recited: "\(transcript.text)"
            GPS Location: \(location)

            ACTIVE CONTEXT: Subject: \(subject) | Year: \(year) | Location: \(loc)

            Identify the song and artist from the lyrics. Resolve in the context of the current \
            triad — the identified artist becomes the new subject, the location stays as \(loc), \
            and the year should flex to the song's release year or the artist's peak era at that location. \
            If unidentifiable, keep the current subject and triad.
            """
        }

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

    private func buildStreamingRequest(userMessage: String) throws -> URLRequest {
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
            "stream": true,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Streaming

    /// Stream a request via SSE, calling `onUpdate` with partial results at parse thresholds.
    /// Returns the final complete result.
    private func streamRequest(
        _ request: URLRequest,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void
    ) async throws -> ClaudeResult {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeServiceError.noResponse
        }

        if httpResponse.statusCode != 200 {
            // Read full error body
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let body = String(data: errorData, encoding: .utf8) ?? "unknown"
            print("[Claude] API error \(httpResponse.statusCode): \(body)")
            throw ClaudeServiceError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        var textBuffer = ""
        var lastParseLength = 0

        for try await line in bytes.lines {
            try Task.checkCancellation()

            // SSE format: lines starting with "data: "
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]" else { break }

            // Parse SSE event JSON
            guard let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
                continue
            }

            // Extract text from content_block_delta events
            guard event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else {
                continue
            }

            textBuffer += text

            // Determine parse threshold based on buffer size
            let bufLen = textBuffer.count
            let shouldParse: Bool
            if bufLen < 150 {
                shouldParse = false
            } else if bufLen < 400 {
                shouldParse = bufLen - lastParseLength >= 250
            } else if bufLen < 2000 {
                // Entity core objects (~150 chars each)
                shouldParse = bufLen - lastParseLength >= 150
            } else {
                // Descriptions (~300 chars each)
                shouldParse = bufLen - lastParseLength >= 300
            }

            if shouldParse {
                lastParseLength = bufLen
                let partial = parseClaudeResponse(textBuffer, isPartial: true)
                if partial.subject != "Observation" {
                    onUpdate(partial)
                }
            }
        }

        // Final authoritative parse
        print("[Claude] Stream complete, buffer: \(textBuffer.count) chars")
        let finalResult = parseClaudeResponse(textBuffer, isPartial: false)
        print("[Claude] Response: \(textBuffer.prefix(200))")
        return finalResult
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

    private func parseClaudeResponse(_ text: String, isPartial: Bool = false) -> ClaudeResult {
        let cleaned = stripCodeFences(text)

        guard let data = cleaned.data(using: .utf8) else {
            if !isPartial {
                print("[Claude] PARSE FAIL: could not convert to UTF-8 data")
                print("[Claude] Raw text (\(text.count) chars): \(text.prefix(500))")
            }
            return fallbackResult(text)
        }

        // Try parsing as-is first
        if let json = tryParseJSON(data) {
            return buildResult(from: json, rawText: text, isPartial: isPartial)
        }

        // Attempt to repair truncated JSON
        if !isPartial {
            print("[Claude] Initial parse failed, attempting JSON repair (\(cleaned.count) chars)")
        }
        if let repaired = repairTruncatedJSON(cleaned),
           let repairedData = repaired.data(using: .utf8),
           let json = tryParseJSON(repairedData) {
            if !isPartial { print("[Claude] JSON repair succeeded") }
            return buildResult(from: json, rawText: text, isPartial: isPartial)
        }

        if !isPartial {
            print("[Claude] PARSE FAIL: JSON repair also failed")
            print("[Claude] Cleaned text (\(cleaned.count) chars): \(cleaned.prefix(500))")
        }
        return fallbackResult(text)
    }

    private func tryParseJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func buildResult(from json: [String: Any], rawText: String, isPartial: Bool = false) -> ClaudeResult {
        let descriptions = json["entityDescriptions"] as? [[String: Any]]
        let result = ClaudeResult(
            subject: json["subject"] as? String ?? "Unknown",
            subjectType: json["subjectType"] as? String ?? "unknown",
            birthInfo: json["birthInfo"] as? String ?? "",
            place: json["place"] as? String ?? "Unknown",
            year: json["year"] as? Int ?? Calendar.current.component(.year, from: .now),
            bio: json["bio"] as? String ?? "",
            narrative: json["narrative"] as? String ?? rawText,
            connections: parseEntities(json["entities"], descriptions: descriptions),
            keyArtists: (json["keyArtists"] as? [String]) ?? [],
            isPartial: isPartial
        )
        if !isPartial {
            print("[Claude] Parsed OK: subject=\(result.subject), place=\(result.place), year=\(result.year), entities=\(result.connections.count)")
        }
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
            keyArtists: [],
            isPartial: false
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

    private func parseEntities(_ raw: Any?, descriptions: [[String: Any]]? = nil) -> [CultureConnection] {
        guard let array = raw as? [[String: Any]] else { return [] }

        // Build a name→description lookup from entityDescriptions
        var descriptionMap: [String: String] = [:]
        if let descs = descriptions {
            for d in descs {
                if let name = d["name"] as? String, let desc = d["description"] as? String {
                    descriptionMap[name.uppercased()] = desc
                }
            }
        }

        return array.compactMap { item in
            guard let rawName = item["name"] as? String,
                  let relationship = item["relationship"] as? String else { return nil }
            let name = firstLine(rawName) ?? rawName
            let subtitle = firstLine(item["subtitle"] as? String)
            let entityType = (item["entityType"] as? String)
                .flatMap { EntityType(rawValue: $0) } ?? .peer
            let relevance = item["relevance"] as? Double ?? 0.5
            // Prefer entityDescriptions lookup, fall back to inline description
            let description = descriptionMap[name.uppercased()]
                ?? item["description"] as? String
                ?? ""
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

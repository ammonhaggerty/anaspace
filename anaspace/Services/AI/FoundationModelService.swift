import Foundation
import FoundationModels

// MARK: - Foundation Model Service

@Observable @MainActor
final class FoundationModelService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = false
    private var entityDetailCache: [String: EntityDetail] = [:]
    private var preloadTask: Task<Void, Never>?

    // MARK: - ObservationService

    func activate() async throws {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            isAvailable = true
        case .unavailable(let reason):
            isAvailable = false
            print("[FM] Model unavailable: \(reason)")
        @unknown default:
            isAvailable = false
        }
    }

    func deactivate() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    // MARK: - Tier 1 Instructions

    private let tier1Instructions = """
        You are a cultural context engine. Given a subject, place, and year, build a culture map \
        of 8 connected entities spanning music, art, events, venues, and movements. \
        Each entity must connect to the subject in this specific place and time period. \
        Use the searchMusic tool to verify artist names and discover related musicians. \
        Use the searchWikiData tool to find cultural events, venues, and movements. \
        Entity names must be ALL CAPS, max 20 characters. \
        Entity types: collaborator, peer, influence, follower, creation, place, event, movement. \
        Reserve relevance 0.9+ for direct collaborators only.
        """

    private let tier3Instructions = """
        Write a short bio and connection description for the given entity.
        """

    // MARK: - Tier 1: Culture Map Generation

    private func generateCultureMap(
        prompt: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void
    ) async throws -> ClaudeResult {
        let start = CFAbsoluteTimeGetCurrent()
        entityDetailCache.removeAll()

        let session = LanguageModelSession(
            tools: [MusicSearchTool(), WikiDataTool()],
            instructions: tier1Instructions
        )

        let stream = session.streamResponse(
            to: prompt,
            generating: CultureMap.self
        )

        var finalResult: ClaudeResult?
        for try await partial in stream {
            let partialResult = partial.content.toClaudeResult()
            // Only emit updates once we have a subject
            if partialResult.subject != "..." {
                onUpdate(partialResult)
                finalResult = partialResult
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("[FM] Tier 1 completed in \(String(format: "%.2f", elapsed))s")

        guard var result = finalResult else {
            throw FoundationModelError.emptyResponse
        }

        // Mark as no longer streaming
        result = ClaudeResult(
            subject: result.subject,
            subjectType: result.subjectType,
            birthInfo: result.birthInfo,
            place: result.place,
            year: result.year,
            bio: result.bio,
            narrative: result.narrative,
            connections: result.connections,
            keyArtists: result.keyArtists,
            isStreaming: false
        )

        // Kick off background entity detail preloading
        preloadEntityDetails(for: result)

        return result
    }

    // MARK: - Tier 3: Entity Detail Loading

    private func preloadEntityDetails(for result: ClaudeResult) {
        preloadTask?.cancel()
        preloadTask = Task {
            // Preload top 3 entities by relevance
            let top3 = result.connections
                .sorted { $0.relevance > $1.relevance }
                .prefix(3)

            await withTaskGroup(of: Void.self) { group in
                for entity in top3 {
                    group.addTask {
                        await self.loadEntityDetail(
                            name: entity.name,
                            entityType: entity.entityType.rawValue,
                            relationship: entity.relationship,
                            subject: result.subject,
                            place: result.place,
                            year: result.year
                        )
                    }
                }
            }
        }
    }

    @discardableResult
    func loadEntityDetail(
        name: String, entityType: String, relationship: String,
        subject: String, place: String, year: Int
    ) async -> EntityDetail? {
        if let cached = entityDetailCache[name] { return cached }

        let prompt = "\(name) (\(entityType)), \(place) \(year). Connection to \(subject): \(relationship)"

        do {
            let start = CFAbsoluteTimeGetCurrent()
            let session = LanguageModelSession(instructions: tier3Instructions)
            let response = try await session.respond(to: prompt, generating: EntityDetail.self)
            let detail = response.content
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("[FM] Tier 3 (\(name)) completed in \(String(format: "%.2f", elapsed))s")

            entityDetailCache[name] = detail
            return detail
        } catch {
            print("[FM] Tier 3 error for \(name): \(error)")
            return nil
        }
    }

    /// Get cached entity detail or load on-demand.
    func getEntityDetail(
        for connection: CultureConnection, subject: String, place: String, year: Int
    ) async -> EntityDetail? {
        if let cached = entityDetailCache[connection.name] { return cached }
        return await loadEntityDetail(
            name: connection.name,
            entityType: connection.entityType.rawValue,
            relationship: connection.relationship,
            subject: subject,
            place: place,
            year: year
        )
    }

    // MARK: - Prompt Builders

    private func buildObservationPrompt(from signals: ObservationSignals) -> String {
        var parts: [String] = []

        if let shazam = signals.shazamResult {
            parts.append("Music identified: \(shazam.title) by \(shazam.artist) (\(shazam.releaseYear ?? 0))")
            if let genre = shazam.genres.first { parts.append("Genre: \(genre)") }
        }

        if let transcript = signals.transcript {
            parts.append("User said: \"\(transcript.text)\"")
        }

        if let loc = signals.location {
            let label = [loc.city, loc.state, loc.country].compactMap { $0 }.joined(separator: ", ")
            parts.append("Location: \(label)")
        }

        // Include active triad context if available
        if let activeSubject = signals.activeSubject {
            parts.append("Current subject: \(activeSubject)")
        }
        if let activeYear = signals.activeYear {
            parts.append("Current year: \(activeYear)")
        }

        parts.append("Build the culture map.")
        return parts.joined(separator: "\n")
    }

    private func buildSubjectChangePrompt(
        connection: CultureConnection?, newSubject: String, priorSubject: String,
        location: String, year: Int
    ) -> String {
        var prompt = "Change subject from \(priorSubject) to \(newSubject)."
        if let conn = connection {
            prompt += " Type: \(conn.entityType.rawValue). Relationship: \(conn.relationship)."
        }
        prompt += "\nLocation: \(location). Year: \(year)."
        prompt += "\nInclude \(priorSubject) as a connection."
        prompt += "\nBuild the culture map for \(newSubject)."
        return prompt
    }

    private func buildYearChangePrompt(subject: String, year: Int, location: String) -> String {
        """
        Subject: \(subject). Location: \(location). Year changed to \(year).
        Find the artist or musician most connected to \(subject)'s legacy who was active \
        in \(location) in \(year). The subject may change. Build the culture map.
        """
    }

    private func buildLocationChangePrompt(
        subject: String, subjectType: String, year: Int, location: String
    ) -> String {
        """
        Subject: \(subject) (\(subjectType)). Year: \(year). Location changed to \(location).
        Find the closest cultural analog from \(location). New subject must be FROM or \
        synonymous with \(location). Build the culture map.
        """
    }

    // MARK: - 5 Query Types (ClaudeService-compatible API)

    func processObservation(
        from signals: ObservationSignals,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let prompt = buildObservationPrompt(from: signals)
        return try await generateCultureMap(prompt: prompt, onUpdate: onUpdate)
    }

    func processSubjectChange(
        connection: CultureConnection? = nil, newSubject: String, priorSubject: String,
        location: String, year: Int,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let prompt = buildSubjectChangePrompt(
            connection: connection, newSubject: newSubject, priorSubject: priorSubject,
            location: location, year: year
        )
        return try await generateCultureMap(prompt: prompt, onUpdate: onUpdate)
    }

    func processYearChange(
        subject: String, year: Int, location: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let prompt = buildYearChangePrompt(subject: subject, year: year, location: location)
        return try await generateCultureMap(prompt: prompt, onUpdate: onUpdate)
    }

    func processLocationChange(
        subject: String, subjectType: String, year: Int, location: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let prompt = buildLocationChangePrompt(
            subject: subject, subjectType: subjectType, year: year, location: location
        )
        return try await generateCultureMap(prompt: prompt, onUpdate: onUpdate)
    }

    func processShortcutQuery(
        prompt: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        return try await generateCultureMap(prompt: prompt, onUpdate: onUpdate)
    }

    // MARK: - Fallback

    static func fallbackResult(subject: String = "Unknown") -> ClaudeResult {
        ClaudeResult(
            subject: subject,
            subjectType: "artist",
            birthInfo: "",
            place: "",
            year: Calendar.current.component(.year, from: .now),
            bio: "",
            narrative: "",
            connections: [],
            keyArtists: [],
            isStreaming: false
        )
    }
}

// MARK: - Error

enum FoundationModelError: Error {
    case emptyResponse
    case modelUnavailable
}

import Foundation
import FoundationModels

// MARK: - Foundation Model Service

@Observable @MainActor
final class FoundationModelService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = false
    private var entityDetailCache: [String: EntityDetail] = [:]
    private var preloadTask: Task<Void, Never>?

    /// Optional MusicKit service for current-decade artist discovery.
    var musicService: MusicService?

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

    // MARK: - Diagnostic

    /// Run simple factual questions to test model knowledge. Check Xcode console.
    func runDiagnostic() async {
        print("[FM DIAGNOSTIC] Starting...")
        let questions = [
            "Which music artist FROM San Francisco was most popular in 1984? Answer with just the name.",
            "Who is the most iconic music artist FROM San Francisco in 1984? Just the name.",
            "Which music artist FROM San Francisco was most popular in 1968? Answer with just the name.",
            "Who is the most iconic punk artist FROM London in 1977? Just the name.",
            "Which musician FROM Detroit was most famous in 1965? Just the name.",
            "Which musician FROM Seattle was most famous in 1992? Just the name.",
        ]

        let session = LanguageModelSession()
        for question in questions {
            do {
                let response = try await session.respond(to: question)
                print("[FM DIAGNOSTIC] Q: \(question)")
                print("[FM DIAGNOSTIC] A: \(response.content)")
                print()
            } catch {
                print("[FM DIAGNOSTIC] Q: \(question)")
                print("[FM DIAGNOSTIC] ERROR: \(error)")
                print()
            }
        }
        print("[FM DIAGNOSTIC] Done.")
    }

    /// Test multi-question approach: subject + 8 entity questions, all plain text.
    func runStructuredDiagnostic() async {
        print("[FM MULTI-Q DIAGNOSTIC] Starting...")

        struct TestCase {
            let location: String
            let year: Int
        }
        let tests = [
            TestCase(location: "San Francisco", year: 1984),
            TestCase(location: "San Francisco", year: 1968),
            TestCase(location: "Detroit", year: 1965),
            TestCase(location: "London", year: 1977),
        ]

        for test in tests {
            let start = CFAbsoluteTimeGetCurrent()
            print("[FM MULTI-Q DIAGNOSTIC] \(test.location) \(test.year):")

            do {
                var result: ClaudeResult?
                _ = try await generateCultureMap(
                    subjectQuestion: "Which music artist FROM \(test.location) was most popular in \(test.year)? Answer with just the name.",
                    location: test.location,
                    year: test.year
                ) { r in result = r }

                if let r = result {
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    print("[FM MULTI-Q DIAGNOSTIC] Subject: \(r.subject)")
                    print("[FM MULTI-Q DIAGNOSTIC] Entities: \(r.connections.map { "\($0.name) (\($0.entityType.rawValue))" }.joined(separator: ", "))")
                    print("[FM MULTI-Q DIAGNOSTIC] Birth: \(r.birthInfo)")
                    print("[FM MULTI-Q DIAGNOSTIC] Narrative: \(r.narrative)")
                    print("[FM MULTI-Q DIAGNOSTIC] Total: \(String(format: "%.1f", elapsed))s")
                }
                print()
            } catch {
                print("[FM MULTI-Q DIAGNOSTIC] ERROR: \(error)")
                print()
            }
        }
        print("[FM MULTI-Q DIAGNOSTIC] Done.")
    }

    #if DEBUG
    func runPromptOptimization(timeLimitSeconds: TimeInterval = 300) async -> String {
        let harness = PromptHarness { [weak self] question in
            await self?.ask(question)
        }
        return await harness.run(timeLimitSeconds: timeLimitSeconds)
    }
    #endif

    func deactivate() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    // MARK: - Instructions

    private let tier3Instructions = """
        Write a short bio and connection description for the given entity.
        """

    // MARK: - Entity Questions

    /// Each entity is resolved via a simple, explicit plain-text question.
    /// The on-device model answers simple factual questions accurately (~7/7),
    /// but hallucinates badly with @Generable structured generation.
    private struct EntityQuestion {
        let type: EntityType
        let template: String
        let relevance: Double
    }

    private let entityQuestions: [EntityQuestion] = [
        .init(type: .collaborator, template: "Who did {subject} frequently work with?", relevance: 0.95),
        .init(type: .peer, template: "Name another musician similar to {subject}.", relevance: 0.8),
        .init(type: .influence, template: "Who influenced {subject}?", relevance: 0.7),
        .init(type: .follower, template: "Name a musician influenced by {subject}.", relevance: 0.7),
        .init(type: .creation, template: "What is {subject}'s most famous song?", relevance: 0.85),
        .init(type: .place, template: "Name the most famous concert venue in {place}.", relevance: 0.75),
        .init(type: .event, template: "Name a music festival held in {place}.", relevance: 0.65),
        .init(type: .movement, template: "What music genre is {subject} known for?", relevance: 0.6),
    ]

    // MARK: - Plain-Text Q&A Helpers

    /// Ask a single plain-text question. Returns cleaned answer or nil on failure/refusal.
    private func ask(_ question: String) async -> String? {
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: question)
            let answer = cleanAnswer(response.content)
            return answer
        } catch {
            print("[FM] Q&A error: \(error)")
            return nil
        }
    }

    /// Clean model response to extract just the name/answer.
    private func cleanAnswer(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter out guardrail refusals and chatbot disclaimers
        let refusalPhrases = ["i can't assist", "i cannot", "i'm sorry", "as an ai", "i don't have"]
        if refusalPhrases.contains(where: { text.lowercased().contains($0) }) {
            return nil
        }

        // Strip trailing period
        if text.hasSuffix(".") { text = String(text.dropLast()) }

        // Strip quotes
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // If the answer contains "is" or "was" + name pattern, extract the name after it.
        // e.g. "The most iconic artist from SF in 1968 is Janis Joplin" → "Janis Joplin"
        // e.g. "Janis Joplin's biggest influence was Bessie Smith" → "Bessie Smith"
        for separator in [" is ", " was ", " were ", " are "] {
            if let range = text.range(of: separator, options: .backwards) {
                let afterSep = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'."))
                // Only use the extracted part if it's reasonably short (a name)
                if !afterSep.isEmpty && afterSep.count < 60 {
                    text = afterSep
                    break
                }
            }
        }

        // Strip "The answer is" or similar preambles
        let preambles = ["the answer is ", "that would be ", "it's ", "it is "]
        for preamble in preambles {
            if text.lowercased().hasPrefix(preamble) {
                text = String(text.dropFirst(preamble.count))
            }
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'."))
        return text.isEmpty ? nil : text
    }

    /// Convert exact year to decade string: 1977 → "the 1970s"
    private func decadeString(for year: Int) -> String {
        let decade = (year / 10) * 10
        return "the \(decade)s"
    }

    /// Fill template placeholders with actual values.
    private func fillTemplate(_ template: String, subject: String, place: String, year: Int) -> String {
        template
            .replacingOccurrences(of: "{subject}", with: subject)
            .replacingOccurrences(of: "{place}", with: place)
            .replacingOccurrences(of: "{year}", with: String(year))
            .replacingOccurrences(of: "{decade}", with: decadeString(for: year))
    }

    // MARK: - Culture Map Generation (multi-question Q&A)

    private func generateCultureMap(
        subjectQuestion: String,
        location: String,
        year: Int,
        knownSubject: String? = nil,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void
    ) async throws -> ClaudeResult {
        let start = CFAbsoluteTimeGetCurrent()

        // Cancel any in-flight Tier 3 preloads — they compete for model inference
        preloadTask?.cancel()
        preloadTask = nil
        entityDetailCache.removeAll()

        // Phase 1: Resolve subject via plain text Q&A
        let subject: String
        if let known = knownSubject {
            subject = known
            print("[FM] Phase 1 skipped — subject: \(known)")
        } else {
            // For 2010s+, try MusicKit first — FM is weak on current music
            let decade = (year / 10) * 10
            var resolved: String?

            if decade >= 2010, let discovered = await musicService?.discoverArtist(near: location.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? location) {
                resolved = discovered
                print("[FM] Phase 1 (\(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start))s) via MusicKit: \(discovered)")
            }

            if resolved == nil {
                resolved = await ask(subjectQuestion)
                if let r = resolved {
                    print("[FM] Phase 1 (\(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start))s) via FM: \(r)")
                }
            }

            guard let finalSubject = resolved else {
                throw FoundationModelError.emptyResponse
            }
            subject = finalSubject
        }

        // Emit initial result with subject
        var connections: [CultureConnection] = []
        func emitUpdate(partial: Bool = true) {
            let artistTypes: Set<EntityType> = [.collaborator, .peer, .influence, .follower]
            let keyArtists = connections.filter { artistTypes.contains($0.entityType) }.map { $0.name }
            let result = ClaudeResult(
                subject: subject.uppercased(),
                subjectType: "artist",
                birthInfo: "",
                place: location,
                year: year,
                bio: "",
                narrative: "",
                connections: connections,
                keyArtists: keyArtists,
                isPartial: partial
            )
            onUpdate(result)
        }
        emitUpdate()

        // Phase 2: Ask entity questions (sequential — model serializes inference anyway)
        let city = location.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? location

        for q in entityQuestions {
            let question = fillTemplate(q.template, subject: subject, place: city, year: year)
            if let answer = await ask(question) {
                let displayName = String(answer.prefix(20)).uppercased()
                // Skip duplicates — model sometimes repeats answers
                let isDuplicate = connections.contains { $0.name == displayName }
                if isDuplicate {
                    print("[FM] \(q.type.rawValue): \(displayName) (duplicate, skipped)")
                } else {
                    print("[FM] \(q.type.rawValue): \(displayName)")
                    connections.append(CultureConnection(
                        name: displayName,
                        subtitle: nil,
                        entityType: q.type,
                        relationship: q.type.defaultRelationship(for: subject),
                        relevance: q.relevance,
                        description: "",
                        recommendedSong: nil
                    ))
                    emitUpdate()
                }
            }
        }

        guard !connections.isEmpty else {
            throw FoundationModelError.emptyResponse
        }

        // Phase 3: Get birth info and narrative
        let birthInfo = await ask("When was \(subject) born and where? Format: 'B. 1947, LONDON'. Just that.") ?? ""
        let narrative = await ask("\(subject) in \(city), \(year). One sentence about why. Just the sentence.") ?? ""

        // Final result
        let artistTypes: Set<EntityType> = [.collaborator, .peer, .influence, .follower]
        let keyArtists = connections.filter { artistTypes.contains($0.entityType) }.map { $0.name }
        let result = ClaudeResult(
            subject: subject.uppercased(),
            subjectType: "artist",
            birthInfo: birthInfo,
            place: location,
            year: year,
            bio: "",
            narrative: narrative,
            connections: connections,
            keyArtists: keyArtists,
            isPartial: false
        )
        onUpdate(result)

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("[FM] Culture map completed in \(String(format: "%.1f", elapsed))s (\(connections.count) entities)")

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
                        guard !Task.isCancelled else { return }
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

    // MARK: - 5 Query Types

    func processObservation(
        from signals: ObservationSignals,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let loc = signals.location
        let location = [loc?.city, loc?.state, loc?.country].compactMap { $0 }.joined(separator: ", ")
        let year = signals.activeYear ?? Calendar.current.component(.year, from: .now)

        // Build Phase 1 question from signals
        let subjectQuestion: String
        var knownSubject: String? = nil

        if let transcript = signals.transcript {
            // Voice request — the transcript IS the subject query
            subjectQuestion = "\(transcript.text). Which music artist is most relevant? Answer with just the name."
        } else if let shazam = signals.shazamResult {
            // Shazam match — the artist is the subject
            knownSubject = shazam.artist
            subjectQuestion = "" // Won't be used
        } else if let active = signals.activeSubject {
            knownSubject = active
            subjectQuestion = ""
        } else {
            subjectQuestion = "Name a famous \(decadeString(for: year)) musician from \(location)."
        }

        return try await generateCultureMap(
            subjectQuestion: subjectQuestion, location: location, year: year,
            knownSubject: knownSubject, onUpdate: onUpdate
        )
    }

    func processSubjectChange(
        connection: CultureConnection? = nil, newSubject: String, priorSubject: String,
        location: String, year: Int,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        // Subject is already known — user clicked on an entity
        return try await generateCultureMap(
            subjectQuestion: "", location: location, year: year,
            knownSubject: newSubject, onUpdate: onUpdate
        )
    }

    func processYearChange(
        subject: String, year: Int, location: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let city = location.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? location
        let question = "Who is the closest cultural match to \(subject) from \(city) in \(decadeString(for: year))?"
        return try await generateCultureMap(
            subjectQuestion: question, location: location, year: year, onUpdate: onUpdate
        )
    }

    func processLocationChange(
        subject: String, subjectType: String, year: Int, location: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        let question = "Who is the closest cultural analog to \(subject) FROM \(location)? Just the name."
        return try await generateCultureMap(
            subjectQuestion: question, location: location, year: year, onUpdate: onUpdate
        )
    }

    func processShortcutQuery(
        prompt: String, location: String = "", year: Int = 0,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void = { _ in }
    ) async throws -> ClaudeResult {
        // Prompt is already a simple, direct question — pass through as-is
        let resolvedYear = year > 0 ? year : Calendar.current.component(.year, from: .now)
        return try await generateCultureMap(
            subjectQuestion: prompt, location: location, year: resolvedYear, onUpdate: onUpdate
        )
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
            isPartial: false
        )
    }
}

// MARK: - Error

enum FoundationModelError: Error {
    case emptyResponse
    case modelUnavailable
}

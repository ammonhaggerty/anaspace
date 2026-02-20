# Apple Foundation Models Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Claude Haiku with on-device Apple Foundation Models for culture map generation, using MusicKit and WikiData tools for grounding.

**Architecture:** Three-tier fresh-session model. Tier 1 generates the culture map with tool access. Tier 2 is direct MusicKit (no model). Tier 3 generates entity details on-demand. All output converts to existing `ClaudeResult` type so nothing downstream changes.

**Tech Stack:** FoundationModels framework, @Generable macro, MusicKit, WikiData REST API, Swift 6 concurrency

**Design Doc:** `docs/plans/2026-02-20-apple-foundation-models-design.md`

---

### Task 1: Raise Deployment Target to iOS 26

**Files:**
- Modify: `anaspace.xcodeproj/project.pbxproj` (deployment target settings)

**Step 1: Update deployment target**

Open the Xcode project and change the deployment target from iOS 17 to iOS 26 for all targets. Use Xcode build settings or sed on the pbxproj.

```bash
# Via Xcode command line
cd /Users/ammon.haggerty/Development/ios/anaspace
xcodebuild -project anaspace.xcodeproj -scheme anaspace -showBuildSettings | grep IPHONEOS_DEPLOYMENT_TARGET
```

Change `IPHONEOS_DEPLOYMENT_TARGET` from `17.0` to `26.0` in project settings (both project-level and target-level).

**Step 2: Verify build still compiles**

```bash
# Build for simulator via XcodeBuildMCP
```

Expected: Build succeeds. Deprecation warnings for iOS 17 APIs may appear — ignore for now.

**Step 3: Commit**

```bash
git add anaspace.xcodeproj/project.pbxproj
git commit -m "Raise deployment target to iOS 26 for Foundation Models"
```

---

### Task 2: Create @Generable Types

**Files:**
- Create: `anaspace/Services/AI/GenerableTypes.swift`

**Step 1: Write GenerableTypes.swift**

```swift
import FoundationModels

// MARK: - Tier 1: Culture Map

@Generable(description: "A culture map anchored to a subject, place, and year")
struct CultureMap {
    @Guide(description: "Primary subject name, ALL CAPS, max 20 characters")
    var subject: String

    @Guide(description: "One of: artist, band, album, venue, event, movement, producer, label")
    var subjectType: String

    @Guide(description: "Birth or founding info, e.g. B. 1942, LONDON")
    var birthInfo: String

    @Guide(description: "City, State | Country")
    var place: String

    @Guide(description: "Anchoring year")
    var year: Int

    @Guide(description: "8 culturally connected entities", .count(8))
    var entities: [CultureEntity]

    @Guide(description: "5 artist names for playlist. Empty array if subject is an artist.", .count(0...5))
    var keyArtists: [String]

    @Guide(description: "One sentence connecting subject to place and year")
    var narrative: String
}

@Generable(description: "A culturally connected entity")
struct CultureEntity {
    @Guide(description: "Entity name, ALL CAPS, max 20 characters")
    var name: String

    @Guide(description: "Optional distinguishing detail, or empty string")
    var subtitle: String

    @Guide(description: "One of: collaborator, peer, influence, follower, creation, place, event, movement")
    var entityType: String

    @Guide(description: "One sentence: how this entity connects to the subject in this place and year")
    var relationship: String

    @Guide(.range(0.0...1.0), description: "Relevance score, 0.9+ reserved for direct collaborators")
    var relevance: Double
}

// MARK: - Tier 3: Entity Detail

@Generable(description: "Detailed information about a culture map entity")
struct EntityDetail {
    @Guide(description: "2 paragraph bio grounded in the specific year and place, 300-400 characters")
    var bio: String

    @Guide(description: "200-300 characters explaining specific connection to the subject")
    var description: String

    @Guide(description: "A song title by or associated with this entity, or empty string if none")
    var recommendedSong: String
}

// MARK: - CultureMap → ClaudeResult Conversion

extension CultureMap {
    /// Convert a fully generated CultureMap to a ClaudeResult for downstream compatibility.
    func toClaudeResult(isStreaming: Bool = false) -> ClaudeResult {
        let connections = entities.map { entity in
            CultureConnection(
                name: entity.name,
                subtitle: entity.subtitle.isEmpty ? nil : entity.subtitle,
                entityType: EntityType(rawValue: entity.entityType) ?? .peer,
                relationship: entity.relationship,
                relevance: entity.relevance,
                description: "",  // Filled by Tier 3 on-demand
                recommendedSong: nil  // Filled by Tier 3 on-demand
            )
        }

        return ClaudeResult(
            subject: subject,
            subjectType: subjectType,
            birthInfo: birthInfo,
            place: place,
            year: year,
            bio: "",  // Filled by Tier 3 on-demand
            narrative: narrative,
            connections: connections,
            keyArtists: keyArtists,
            isStreaming: isStreaming
        )
    }
}

extension CultureMap.PartiallyGenerated {
    /// Convert a partially generated CultureMap to a streaming ClaudeResult.
    func toClaudeResult() -> ClaudeResult {
        let connections = (entities ?? []).compactMap { partial -> CultureConnection? in
            guard let name = partial.name, !name.isEmpty else { return nil }
            return CultureConnection(
                name: name,
                subtitle: (partial.subtitle ?? "").isEmpty ? nil : partial.subtitle,
                entityType: EntityType(rawValue: partial.entityType ?? "peer") ?? .peer,
                relationship: partial.relationship ?? "",
                relevance: partial.relevance ?? 0.5,
                description: "",
                recommendedSong: nil
            )
        }

        return ClaudeResult(
            subject: subject ?? "...",
            subjectType: subjectType ?? "artist",
            birthInfo: birthInfo ?? "",
            place: place ?? "",
            year: year ?? 0,
            bio: "",
            narrative: narrative ?? "",
            connections: connections,
            keyArtists: keyArtists ?? [],
            isStreaming: true
        )
    }
}
```

Note: `narrative` is placed last in `CultureMap` (after entities) so the model generates it as a synthesis. But `keyArtists` is before `narrative` because it depends on the entities but not on the narrative.

**Step 2: Add file to Xcode project and build**

Add `GenerableTypes.swift` to the anaspace target. Build to verify @Generable macros compile.

Expected: Clean build. If @Generable macro expansion issues occur, check that deployment target is iOS 26.

**Step 3: Commit**

```bash
git add anaspace/Services/AI/GenerableTypes.swift
git commit -m "Add @Generable types for Foundation Models culture map"
```

---

### Task 3: Create MusicSearch Tool

**Files:**
- Create: `anaspace/Services/AI/MusicSearchTool.swift`

**Step 1: Write MusicSearchTool.swift**

```swift
import FoundationModels
import MusicKit

// MARK: - MusicSearch Tool

struct MusicSearchTool: Tool {
    let name = "searchMusic"
    let description = "Search Apple Music for artists, albums, and songs"

    @Generable
    struct Arguments {
        @Guide(description: "Artist or album name to search")
        var query: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        guard MusicAuthorization.currentStatus == .authorized else {
            return ToolOutput("Music search unavailable.")
        }

        var request = MusicCatalogSearchRequest(term: arguments.query, types: [Artist.self, Album.self])
        request.limit = 5

        let response = try await request.response()

        var parts: [String] = []

        // Artists
        for artist in response.artists.prefix(3) {
            let genres = artist.genreNames.prefix(2).joined(separator: ", ")
            var line = "\(artist.name)"
            if !genres.isEmpty { line += " (\(genres))" }
            parts.append(line)
        }

        // Albums with years
        for album in response.albums.prefix(3) {
            let year = album.releaseDate.map { "\(Calendar.current.component(.year, from: $0))" } ?? "?"
            parts.append("\(album.artistName) - \(album.title) (\(year))")
        }

        let result = parts.joined(separator: "; ")
        return ToolOutput(String(result.prefix(300)))
    }
}
```

**Step 2: Build to verify compilation**

Expected: Clean build.

**Step 3: Commit**

```bash
git add anaspace/Services/AI/MusicSearchTool.swift
git commit -m "Add MusicKit search tool for Foundation Models"
```

---

### Task 4: Create WikiData Tool

**Files:**
- Create: `anaspace/Services/AI/WikiDataTool.swift`

**Step 1: Write WikiDataTool.swift**

Uses the WikiData MediaWiki search API (simple keyword search, no SPARQL). Returns compact entity summaries.

```swift
import FoundationModels
import Foundation

// MARK: - WikiData Tool

struct WikiDataTool: Tool {
    let name = "searchWikiData"
    let description = "Search for cultural events, venues, movements, and people by place and time period"

    @Generable
    struct Arguments {
        @Guide(description: "Search query combining topic and place, e.g. 'punk venues London' or 'jazz festival Detroit'")
        var query: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let results = try await searchWikiData(query: arguments.query)
        guard !results.isEmpty else {
            return ToolOutput("No results found.")
        }

        let text = results.prefix(5).joined(separator: "; ")
        return ToolOutput(String(text.prefix(400)))
    }

    // MARK: - WikiData API

    private func searchWikiData(query: String) async throws -> [String] {
        // Step 1: Search for entities matching the query
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let searchResponse = try JSONDecoder().decode(WikiSearchResponse.self, from: data)

        return searchResponse.search.map { entity in
            var line = entity.label
            if let desc = entity.description {
                line += " — \(String(desc.prefix(100)))"
            }
            return line
        }
    }
}

// MARK: - WikiData Response Types

private struct WikiSearchResponse: Decodable {
    let search: [WikiEntity]
}

private struct WikiEntity: Decodable {
    let id: String
    let label: String
    let description: String?
}
```

**Step 2: Build to verify compilation**

Expected: Clean build.

**Step 3: Commit**

```bash
git add anaspace/Services/AI/WikiDataTool.swift
git commit -m "Add WikiData search tool for Foundation Models"
```

---

### Task 5: Create FoundationModelService — Core + Streaming

**Files:**
- Create: `anaspace/Services/AI/FoundationModelService.swift`

This is the main service. It replaces ClaudeService with the same public API.

**Step 1: Write FoundationModelService.swift**

```swift
import Foundation
import FoundationModels

// MARK: - Foundation Model Service

@Observable @MainActor
final class FoundationModelService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = false
    private var entityDetailCache: [String: EntityDetail] = [:]
    private var preloadTask: Task<Void, Never>?

    private let musicSearchTool: MusicSearchTool
    weak var musicService: MusicService?

    init(musicService: MusicService? = nil) {
        self.musicService = musicService
        self.musicSearchTool = MusicSearchTool()
    }

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

    func deactivate() {}

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
    You are a cultural context engine. Write a bio and description for the given entity, \
    grounded in the specific place and year provided. Bio should be 2 paragraphs, \
    300-400 characters. Description should explain the specific connection to the subject, \
    200-300 characters.
    """

    // MARK: - Tier 1: Culture Map Generation

    private func generateCultureMap(
        prompt: String,
        onUpdate: @MainActor @Sendable (ClaudeResult) -> Void
    ) async throws -> ClaudeResult {
        let start = CFAbsoluteTimeGetCurrent()
        entityDetailCache.removeAll()

        let session = LanguageModelSession(
            instructions: tier1Instructions,
            tools: [musicSearchTool, WikiDataTool()]
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
        // Check cache
        if let cached = entityDetailCache[name] { return cached }

        let prompt = """
        Entity: \(name) (\(entityType))
        Connection to \(subject): \(relationship)
        Place: \(place), Year: \(year)
        """

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
    func getEntityDetail(for connection: CultureConnection, subject: String, place: String, year: Int) async -> EntityDetail? {
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
            if let genres = shazam.genres.first { parts.append("Genre: \(genres)") }
        }

        if let transcript = signals.transcript {
            parts.append("User said: \"\(transcript.text)\"")
        }

        if let loc = signals.location {
            let label = [loc.city, loc.state, loc.country].compactMap { $0 }.joined(separator: ", ")
            parts.append("Location: \(label)")
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
```

**Step 2: Add to Xcode project and build**

Expected: Clean build. The service is not yet wired into ServiceManager.

**Step 3: Commit**

```bash
git add anaspace/Services/AI/FoundationModelService.swift
git commit -m "Add FoundationModelService with 5 query types and streaming"
```

---

### Task 6: Wire Into ServiceManager

**Files:**
- Modify: `anaspace/Services/ServiceManager.swift`

**Step 1: Swap ClaudeService for FoundationModelService**

In `ServiceManager.swift`, change the `claude` property declaration:

```swift
// Before (line 14):
let claude = ClaudeService()

// After:
let claude = FoundationModelService()
```

**Step 2: Wire musicService reference in init**

In the `init()` method, add:

```swift
claude.musicService = music
```

**Step 3: Remove API key checks**

Search ServiceManager for references to `claude.isAvailable` and `claude.apiKey`. The `isAvailable` check stays (Foundation Models has its own availability). Remove any API key-specific logic.

Check `ClaudeService` call sites in ServiceManager:
- `processResults()` line ~308: `try await claude.activate()` — keep, FoundationModelService implements `activate()`
- `progress.logEvent("Claude API key: \(claude.isAvailable ...)")` — update log message
- All 5 query methods route through `claude.process*()` — no changes needed, signatures match

**Step 4: Check for other ClaudeService references in the codebase**

Search all Swift files for `ClaudeService`, `ClaudeModel`, `apiKey`, `claude.` to find any remaining references that need updating. Key places to check:
- `AnaspaceApp.swift` — may set API key on launch
- `ContentView.swift` — may reference claude service
- Any settings/debug views

**Step 5: Build and verify**

Build for simulator. Fix any compilation errors from the swap.

**Step 6: Commit**

```bash
git add anaspace/Services/ServiceManager.swift
# Add any other modified files
git commit -m "Wire FoundationModelService into ServiceManager, replacing Claude"
```

---

### Task 7: Handle Remaining Integration Points

**Files:**
- Modify: `anaspace/App/AnaspaceApp.swift` (remove API key setup)
- Modify: Any files referencing ClaudeService directly

**Step 1: Find and update all ClaudeService references**

```bash
# Search for all references
grep -rn "ClaudeService\|apiKey\|CLAUDE_API_KEY\|claude\.apiKey" anaspace/ --include="*.swift"
```

For each reference:
- Remove API key loading from environment/config
- Remove API key assignment to service
- Remove API key availability warnings in UI
- Keep any `claude.isAvailable` checks — they now check Foundation Model availability

**Step 2: Update Info.plist**

Remove `CLAUDE_API_KEY` entry from Info.plist if present (no longer needed on this branch).

**Step 3: Build and verify clean compilation**

Full build for simulator. All compiler errors must be resolved.

**Step 4: Commit**

```bash
git add -A
git commit -m "Remove Claude API key dependencies, clean up integration"
```

---

### Task 8: Build, Run on Device, and Test

**Prerequisites:** Physical iPhone 15 Pro+ with Apple Intelligence enabled, running iOS 26.

**Step 1: Build for device**

Build and install on physical device.

**Step 2: Test each query type**

Test checklist (log observations for each):

| Test | Action | What to observe |
|------|--------|----------------|
| Cold observation | Tap Observe with music playing | Does Tier 1 produce 8 entities? Latency? Quality? |
| Hold observation | Hold Observe and speak | Does transcript influence result? |
| Subject change | Tap an entity on the culture map | Does it generate a new map? Does prior subject appear? |
| Year change | Adjust the year | Does it find a relevant subject for new year? |
| Location change | Select new location on map | Does new subject come from the new location? |
| Shortcut query | Use an IDEAS card | Does freeform query produce results? |
| Streaming | Watch progressive rendering | Do entities appear incrementally? |
| Music playback | After observation resolves | Does the playlist load from entity names? |
| Guardrail test | Try a potentially filtered subject | Does the app handle guardrail violations gracefully? |
| Tool grounding | Check entity accuracy | Are entities real? Do MusicKit results appear in log? |

**Step 3: Log performance metrics**

The `[FM]` log lines show timing for each tier. Document:
- Tier 1 average latency
- Tier 3 average latency per entity
- Any `exceededContextWindowSize` errors
- Any `guardrailViolation` errors
- Overall quality assessment (1-5 scale per test)

**Step 4: Commit findings**

```bash
# Add a TESTING_NOTES.md with findings
git add docs/plans/TESTING_NOTES.md
git commit -m "Add Foundation Models testing notes and observations"
```

---

## Task Dependency Graph

```
Task 1 (iOS 26 target)
  └──> Task 2 (@Generable types)
         ├──> Task 3 (MusicSearch tool)
         ├──> Task 4 (WikiData tool)
         └──> Task 5 (FoundationModelService)
                └──> Task 6 (ServiceManager wiring)
                       └──> Task 7 (Clean up integration)
                              └──> Task 8 (Device testing)
```

Tasks 3 and 4 can be done in parallel. All others are sequential.

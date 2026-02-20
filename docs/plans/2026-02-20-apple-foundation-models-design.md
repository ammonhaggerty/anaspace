# Apple Foundation Models Integration Design

**Date:** 2026-02-20
**Branch:** `feature/apple-foundation-models`
**Status:** Experimental — full swap of Claude Haiku for on-device Foundation Models

## Goal

Replace the Claude API integration with Apple's on-device Foundation Models framework to evaluate feasibility, quality, and performance for culture map generation. This is an exploratory branch — not a production cutover.

## Constraints

- **4,096 tokens total per session** (input + output combined). The current Claude system prompt alone exceeds this. Decomposition is mandatory.
- **Weak world knowledge.** The 3B on-device model is not designed for factual Q&A. Tools (MusicKit, WikiData) provide grounding data.
- **iOS 26+ / A17 Pro+** required. Deployment target raised on this branch.
- **Aggressive content filtering.** Guardrail violations possible for some subjects; must handle gracefully.

## Architecture: Three-Tier Fresh-Session Model

Each tier creates a fresh `LanguageModelSession` with its own full 4,096-token budget. No session reuse, no context accumulation.

```
Tier 1: Culture Map Generation (~750 tokens)
┌─────────────────┐    ┌──────────────────┐
│ FM Session       │───>│ MusicKit Tool    │
│ instructions     │    │ (artists, albums)│
│ + prompt         │    ├──────────────────┤
│                  │───>│ WikiData Tool    │
│                  │    │ (events, venues, │
│                  │    │  movements)      │
└────────┬─────────┘    └──────────────────┘
         v
  CultureMap: subject + 8 entities (names, types, relationships)

Tier 2: Playlist (No model — direct MusicKit API)
  Existing MusicQueueBuilder uses entity names + year

Tier 3: Entity Details (~280 tokens per entity, on-demand)
┌─────────────────┐
│ FM Session       │──> EntityDetail: bio + description + song
│ (fresh per       │
│  entity)         │
└─────────────────┘
```

### Token Budgets

| Tier | Instructions | Tools | Prompt | Tool Response | Output | Total |
|------|-------------|-------|--------|--------------|--------|-------|
| 1: Culture Map | ~100 | ~120 (2 tools) | ~30 | ~200 | ~400 | ~850 |
| 2: Playlist | — | — | — | — | — | 0 (direct API) |
| 3: Entity Detail | ~50 | 0 | ~30 | 0 | ~200 | ~280 |

All well within the 4,096 limit with room for tool call overhead.

## @Generable Types

### Tier 1: CultureMap

```swift
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

    @Guide(description: "One sentence connecting subject to place and year")
    var narrative: String

    @Guide(description: "8 culturally connected entities", .count(8))
    var entities: [CultureEntity]

    @Guide(description: "5 artist names for playlist. Empty if subject is an artist.", .count(0...5))
    var keyArtists: [String]
}

@Generable(description: "A culturally connected entity")
struct CultureEntity {
    @Guide(description: "Entity name, ALL CAPS, max 20 characters")
    var name: String

    @Guide(description: "Optional distinguishing detail, or empty")
    var subtitle: String

    @Guide(description: "One of: collaborator, peer, influence, follower, creation, place, event, movement")
    var entityType: String

    @Guide(description: "One sentence: how this entity connects to the subject in this place and year")
    var relationship: String

    @Guide(.range(0.0...1.0), description: "Relevance score, 0.9+ for direct collaborators")
    var relevance: Double
}
```

### Tier 3: EntityDetail

```swift
@Generable(description: "Detailed information about a culture map entity")
struct EntityDetail {
    @Guide(description: "2 paragraph bio, 300-400 characters, grounded in specific year and place")
    var bio: String

    @Guide(description: "200-300 characters explaining specific connection to the subject")
    var description: String

    @Guide(description: "A song title by or associated with this entity, or empty")
    var recommendedSong: String
}
```

### Design Rationale

- Property order is deliberate: foundational properties first, summaries/dependent properties last. This improves generation quality.
- `entityType` is a guided String, not a Swift enum. The model handles string guidance better for open-ended categories. We map to the existing `EntityType` enum after generation.
- `CultureEntity` is intentionally compact — no bio or description. Those are Tier 3 on-demand calls, saving ~200 tokens per entity in Tier 1.
- `narrative` is last in CultureMap so the model generates it after all entities, producing a better synthesis.

## Tool Definitions

### MusicSearchTool

Wraps the existing `MusicService` to search Apple Music catalog.

```swift
struct MusicSearchTool: Tool {
    let name = "searchMusic"
    let description = "Search Apple Music for artists, albums, and songs"

    @Generable
    struct Arguments {
        @Guide(description: "Artist or album name to search")
        var query: String

        @Guide(description: "Optional year to filter results near")
        var year: Int?
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        // Search MusicKit catalog
        // Return compact text: "Artist: NAME | Genre: X | Active: Y-Z | Albums: A (year), B (year)"
        // Truncated to ~150 chars to minimize token consumption
    }
}
```

### WikiDataTool

Queries WikiData's public SPARQL API for cultural entities outside the music catalog.

```swift
struct WikiDataTool: Tool {
    let name = "searchWikiData"
    let description = "Search for cultural events, venues, movements, and people by place and year"

    @Generable
    struct Arguments {
        @Guide(description: "What to search for, e.g. 'music venues in Detroit' or 'punk movement London'")
        var query: String

        @Guide(description: "City or region to search in")
        var place: String

        @Guide(description: "Year to center search around")
        var year: Int
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        // Query WikiData SPARQL endpoint
        // Return compact text: "NAME | Type: X | Location: Y | Year: Z | Description: ..."
        // Truncated to ~200 chars to minimize token consumption
    }
}
```

### Tool Design Principles

- **Plain text output**, not JSON. Saves tokens; the model parses prose naturally.
- **Aggressive truncation.** Tool responses capped at 150-200 chars each. Every token of tool output is context consumed.
- **Model decides when to call.** Instructions say tools are available for grounding, but the model can generate from knowledge alone if confident. Avoids unnecessary tool calls.
- **One-sentence descriptions.** Tool definitions serialize into the prompt as JSON schema. Keep descriptions minimal.

## Service Layer

### New Files

```
Services/AI/
├── FoundationModelService.swift  (session management, 5 query types)
├── GenerableTypes.swift          (CultureMap, CultureEntity, EntityDetail)
├── MusicSearchTool.swift         (MusicKit tool)
└── WikiDataTool.swift            (WikiData SPARQL tool)
```

### FoundationModelService

Replaces `ClaudeService`. Same public interface so ServiceManager changes are minimal.

```swift
@Observable @MainActor
final class FoundationModelService {
    private(set) var isAvailable: Bool = false
    private var entityDetailCache: [String: EntityDetail] = [:]

    // Same 5 query types as ClaudeService, same signatures:
    func processObservation(from:, onUpdate:) async throws -> ClaudeResult
    func processSubjectChange(..., onUpdate:) async throws -> ClaudeResult
    func processYearChange(..., onUpdate:) async throws -> ClaudeResult
    func processLocationChange(..., onUpdate:) async throws -> ClaudeResult
    func processShortcutQuery(prompt:, onUpdate:) async throws -> ClaudeResult
}
```

Key behaviors:
- **Returns `ClaudeResult`** by converting from `CultureMap` internally. The entire downstream pipeline (ServiceManager, progress, UI, music queue) stays untouched.
- **Fresh session per call.** No context accumulation.
- **Availability check on init.** Queries `SystemLanguageModel.default.availability`.
- **Prewarm on activate.** Calls `session.prewarm()` for faster first response.

### ServiceManager Changes

Swap one declaration:

```swift
// Before:
let claude = ClaudeService()
// After:
let claude = FoundationModelService()
```

Remove API key checks. Everything else (5 query methods, resolve flow, buildPlayerQueue) stays unchanged.

### Streaming

Foundation Models uses snapshot-based streaming via `PartiallyGenerated` types (not delta SSE).

1. Tier 1 streams `CultureMap.PartiallyGenerated` — subject/type/place fill first, then entities populate one by one.
2. Each snapshot converts to a partial `ClaudeResult` and calls `onUpdate`.
3. Tier 3 entity details load in background or on-demand after Tier 1 completes.

## Entity Detail Loading

```
Culture map resolves (Tier 1)
    |
    |---> UI renders: 8 entity names/types/relationships (immediate)
    |
    |---> Background: preload top 3 entities by relevance (concurrent Tier 3 sessions)
    |
    +---> On-demand: user taps entity -> check cache -> fire Tier 3 if miss (~1s)
```

- **Cache:** `[String: EntityDetail]` dictionary on FoundationModelService. Cleared per observation.
- **Concurrency:** Max 3 parallel Tier 3 sessions via TaskGroup.
- **Expected latency:** ~280 tokens per Tier 3 call, estimated under 1 second.

## Error Handling

### Availability

```swift
switch SystemLanguageModel.default.availability {
case .available:                              // proceed
case .unavailable(.deviceNotEligible):        // permanent — show message
case .unavailable(.appleIntelligenceNotEnabled): // prompt user to enable in Settings
case .unavailable(.modelNotReady):            // downloading — retry after delay
}
```

### Per-Call Errors

| Error | Strategy |
|-------|----------|
| `exceededContextWindowSize` | Retry with truncated tool outputs or skip tool calling |
| `guardrailViolation` | Return minimal result with subject name, empty entities. Log for debugging. |
| Tool call failure (MusicKit/WikiData) | Model continues without tool data. Graceful degradation. |
| Generation timeout (>10s Tier 1, >5s Tier 3) | Cancel and return fallback result |

### Fallback Result

If Tier 1 fails entirely, construct a minimal `ClaudeResult` with the subject name from input signals and empty connections. Prevents UI crashes. Same pattern as the current Claude fallback.

## What This Experiment Will Validate

1. **Knowledge quality:** Can the 3B model generate meaningful cultural connections, or does it hallucinate?
2. **Tool grounding:** How much do MusicKit/WikiData tools improve entity accuracy?
3. **Latency:** Is the three-tier pipeline fast enough for the progressive-rendering UX?
4. **Content filtering:** How often do guardrail violations block legitimate cultural subjects?
5. **Token budget:** Do the estimates hold in practice, or do tool responses push us over?

## Lessons Applied from AppleFoundationMatchMaker

- **Fresh sessions per call** — no context accumulation (the #1 lesson).
- **Aggressive truncation** — keep all inputs/outputs compact.
- **@Generable over raw text** — constrained decoding guarantees valid structure.
- **Prewarm early** — shaves 300-500ms off first generation.
- **Graceful degradation** — AI failure never blocks core functionality.
- **Benchmark from day one** — log generation times and token usage for every call.

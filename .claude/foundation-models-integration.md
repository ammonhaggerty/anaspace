# Foundation Models Integration

**Branch:** `feature/apple-foundation-models`
**Status:** Experimental — ready for device testing
**Requires:** iOS 26+, A17 Pro+, Apple Intelligence enabled

---

## What Changed

This branch replaces the Claude Haiku API with Apple's on-device Foundation Models framework for all culture map generation. The entire downstream pipeline (ServiceManager, UI, music queue) is unchanged — `FoundationModelService` produces the same `ClaudeResult` type that `ClaudeService` did.

### Files Added

| File | Purpose |
|------|---------|
| `Services/AI/FoundationModelService.swift` | Core service — 5 query types, streaming, entity detail cache |
| `Services/AI/GenerableTypes.swift` | `@Generable` structs: CultureMap, CultureEntity, EntityDetail |
| `Services/AI/MusicSearchTool.swift` | Foundation Models Tool wrapping MusicKit catalog search |
| `Services/AI/WikiDataTool.swift` | Foundation Models Tool querying WikiData REST API |

### Files Modified

| File | Change |
|------|--------|
| `Services/ServiceManager.swift` | Swapped `ClaudeService()` for `FoundationModelService()`, updated log messages |
| `Info.plist` | Removed `CLAUDE_API_KEY` entry (no longer needed) |

### Files Kept (Unused)

`Services/AI/ClaudeService.swift` remains in the project but is no longer instantiated. It's preserved for reference and easy revert.

---

## Architecture: Three-Tier Fresh-Session Model

The core constraint is Foundation Models' **4,096 token budget** (input + output combined per session). The old Claude approach used a single massive system prompt (~2,000 tokens) with one API call. That won't fit. Instead, we decompose into three tiers, each creating a fresh `LanguageModelSession`.

```
Tier 1: Culture Map (~850 tokens)
  Fresh session with MusicKit + WikiData tools
  → Generates: subject, 8 entities, narrative, keyArtists
  → Streams via PartiallyGenerated snapshots → ClaudeResult

Tier 2: Playlist (No model — direct MusicKit API)
  Existing MusicQueueBuilder uses entity names + year
  → Zero token cost

Tier 3: Entity Details (~280 tokens each, on-demand)
  Fresh session per entity, no tools
  → Generates: bio, description, recommendedSong
  → Background preloads top 3 by relevance, rest on-demand
  → Cached in entityDetailCache dictionary
```

### Why Fresh Sessions

The #1 lesson from the AppleFoundationMatchMaker reference project: never accumulate context across calls. Each `LanguageModelSession` gets a full 4,096-token budget. Reusing sessions would starve later calls.

---

## @Generable Types

Foundation Models uses the `@Generable` macro for structured output (constrained decoding). The model generates JSON that maps directly to Swift structs — no parsing needed.

### CultureMap (Tier 1 output)

```swift
@Generable struct CultureMap {
    var subject: String        // "SLY STONE"
    var subjectType: String    // "artist"
    var birthInfo: String      // "B. 1943, DENTON, TX"
    var place: String          // "Oakland, CA | USA"
    var year: Int              // 1971
    var entities: [CultureEntity]  // 8 connected entities
    var keyArtists: [String]   // up to 5 playlist names
    var narrative: String      // synthesis sentence (generated last)
}
```

**Property order matters.** Foundational properties first, summaries last. The model generates sequentially, so `narrative` being last means it synthesizes from all prior fields. `keyArtists` before `narrative` ensures playlist names are ready before the summary.

### CultureEntity (nested in CultureMap)

```swift
@Generable struct CultureEntity {
    var name: String           // "LARRY GRAHAM"
    var subtitle: String       // "Bass pioneer" or ""
    var entityType: String     // "collaborator"
    var relationship: String   // "Bassist in Sly's Family Stone..."
    var relevance: Double      // 0.95 (0.9+ = direct collaborator)
}
```

`entityType` is a guided String, not a Swift enum. The model handles string guidance better. We map to `EntityType` enum after generation.

### EntityDetail (Tier 3 output)

```swift
@Generable struct EntityDetail {
    var bio: String            // 300-400 char bio
    var description: String    // 200-300 char connection description
    var recommendedSong: String // song title or ""
}
```

### Conversion Bridge

Both `CultureMap` and `CultureMap.PartiallyGenerated` have `.toClaudeResult()` methods that map to the existing `ClaudeResult` type. This is the only glue between Foundation Models and the rest of the app.

---

## Tools

The on-device 3B model has weak world knowledge. Tools provide factual grounding.

### MusicSearchTool

Wraps `MusicCatalogSearchRequest` from MusicKit. The model calls `searchMusic(query:)` to verify artist names and discover related musicians. Returns plain text (up to 3 artists with genres, up to 3 albums with years), truncated to 300 chars.

### WikiDataTool

Queries WikiData's `wbsearchentities` REST endpoint. The model calls `searchWikiData(query:)` to find cultural entities outside the music catalog — venues, events, movements, historical figures. Returns up to 5 entity labels with descriptions, truncated to 400 chars.

### Tool Design Principles

- **Plain text output**, not JSON. Saves tokens.
- **Aggressive truncation.** Every token of tool output is context consumed.
- **Model decides when to call.** Instructions say tools are available, but the model can skip them if confident.
- **Return type is `String`**, not `ToolOutput` (the WWDC examples show `ToolOutput` but it's not available in the shipped SDK — `String` conforms to the Tool protocol's output requirements).

---

## Streaming

Foundation Models uses snapshot-based streaming via auto-generated `PartiallyGenerated` types.

```swift
let stream = session.streamResponse(to: prompt, generating: CultureMap.self)
for try await partial in stream {
    // partial.content is CultureMap.PartiallyGenerated
    // All properties are Optional — nil means not yet generated
    let result = partial.content.toClaudeResult()
    onUpdate(result)
}
```

The stream yields `ResponseStream.Snapshot` objects. Access the partial via `.content`. Each snapshot is a full picture of what's been generated so far — subject fills first, then entities populate one by one, then narrative last.

---

## Entity Detail Loading

```
Tier 1 completes
  │
  ├─→ UI renders: 8 entity names/types/relationships (immediate)
  │
  ├─→ Background: preload top 3 entities by relevance (concurrent Tier 3 sessions)
  │
  └─→ On-demand: user taps entity → check cache → fire Tier 3 if miss (~1s)
```

Cache is a `[String: EntityDetail]` dictionary on FoundationModelService, cleared each new observation. Max 3 concurrent Tier 3 sessions via `TaskGroup`.

---

## Error Handling

| Error | Strategy |
|-------|----------|
| Model unavailable (not eligible, not enabled, downloading) | `isAvailable = false`, ServiceManager skips FM calls |
| `exceededContextWindowSize` | Caught by stream loop, returns partial result |
| Guardrail violation | Generation fails, returns empty result |
| Tool call failure (MusicKit/WikiData) | Model continues without tool data |
| Empty response (no subject generated) | Throws `FoundationModelError.emptyResponse` |

---

## What to Validate on Device

1. **Knowledge quality** — Can the 3B model produce meaningful cultural connections?
2. **Tool grounding** — Do MusicKit/WikiData tool calls improve accuracy?
3. **Latency** — Is the three-tier pipeline fast enough for progressive rendering?
4. **Content filtering** — How often do guardrail violations block legitimate subjects?
5. **Token budget** — Do tool responses push any tier over the 4,096 limit?
6. **Streaming UX** — Do entities appear incrementally in the UI?

---

## API Quirks Discovered

- `@Guide(description:, .constraint)` — the `description:` label must come before the unnamed constraint parameter. `@Guide(.range(...), description: "...")` does not compile.
- `ToolOutput` shown in WWDC 2025 examples does not exist in the shipped SDK. Tools return `String` directly.
- `LanguageModelSession(tools:, instructions:)` — `tools:` parameter comes before `instructions:`.
- `streamResponse` yields `ResponseStream.Snapshot` with `.content` property, not `PartiallyGenerated` directly.
- `artist.genreNames` in MusicKit is `[String]?` (optional), needs nil-coalescing.

---

## Design Docs

- Full design: `docs/plans/2026-02-20-apple-foundation-models-design.md`
- Implementation plan: `docs/plans/2026-02-20-apple-foundation-models-plan.md`

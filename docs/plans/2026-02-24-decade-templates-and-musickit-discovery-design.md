# Decade Templates & MusicKit Discovery Design

## Goal

Improve FM prompt accuracy by switching to decade-grained language, and fill the "what's hot now" gap by using MusicKit for subject discovery when the decade is 2010s+.

## Problem

The prompt optimization harness revealed two issues:
1. The FM model's knowledge is decade-grained — exact year references ("around 1977") don't improve accuracy and sometimes cause hallucination. Simpler decade phrasing ("the 1970s") works better.
2. The FM model is weak on post-2010 music — it fabricates names or returns legacy artists when asked about current musicians in a location.

## Architecture

Two independent changes, minimal blast radius:

**Change A: Decade-focused FM templates** — Rewrite `entityQuestions` using harness-recommended phrasings with decade language. Several question types drop temporal context entirely since the harness found it unhelpful.

**Change B: MusicKit-first subject discovery for 2010s+** — When decade >= 2010s, query MusicKit's catalog for a relevant artist associated with the location instead of asking the FM. MusicKit's search returns results ranked by relevance/popularity, which surfaces well-known artists associated with a city or region. Falls back to FM if MusicKit is unavailable or returns nothing.

## Change A: Decade Templates

### New Templates (from harness recommendations)

| Type | Template |
|------|----------|
| subject | "Name a famous {decade} musician from {place}." |
| collaborator | "Who did {subject} frequently work with?" |
| peer | "Name another musician similar to {subject}." |
| influence | "Who influenced {subject}?" |
| follower | "Name a musician influenced by {subject}." |
| creation | "What is {subject}'s most famous song?" |
| place | "Name the most famous concert venue in {place}." |
| event | "Name a music festival held in {place}." |
| movement | "What music genre is {subject} known for?" |

### Phrasing Rules (from harness)

- Use simple, direct imperatives: "Name..." or "What is..."
- Avoid combining location + time + artist in a single query
- Request single answers: "most famous" rather than lists
- Keep templates under 10 words
- Use present tense

### Implementation

- New `decadeString(for:)` helper: converts `1977` → `"the 1970s"`, `2024` → `"the 2020s"`
- Add `{decade}` placeholder to `fillTemplate()`
- Only `subject` template uses `{decade}` — the rest drop temporal context
- `{year}` remains available for MusicKit and other services that benefit from precision

## Change B: MusicKit-First Subject Discovery

### Flow

```
generateCultureMap() called with (location, year)
  ↓
Is decade >= 2010s AND MusicKit authorized?
  YES → MusicService.discoverArtist(near: location)
    ↓ got result? → use as subject
    ↓ nil result? → fall back to FM subject question
  NO → FM subject question (with decade language)
  ↓
Subject resolved — proceed with FM relationship questions as today
```

### New Method: `MusicService.discoverArtist(near:)`

```swift
func discoverArtist(near location: String) async -> String?
```

- `MusicCatalogSearchRequest(term: location, types: [Artist.self])`, limit 10
- Returns top result's name, or nil
- MusicKit's relevance ranking naturally surfaces artists associated with the search term

### Edge Cases

- **Location too generic** — returns globally popular artists. Acceptable: still better than FM hallucination.
- **Non-English locations** — MusicKit handles international catalog well (Lagos → Afrobeats, Seoul → K-pop).
- **MusicKit not authorized** — falls back to FM subject question.
- **Small cities** — MusicKit returns nothing → falls back to FM.

## What Doesn't Change

- Culture map data model (ClaudeResult, CultureConnection)
- UI / grid / year picker (stays continuous, not decade-snapped)
- Relationship questions — always FM regardless of decade
- MusicKit playback flow
- Claude API integration

## Files Touched

- `FoundationModelService.swift` — templates, decadeString(), fillTemplate(), MusicKit branch in generateCultureMap()
- `MusicService.swift` — new discoverArtist(near:) method

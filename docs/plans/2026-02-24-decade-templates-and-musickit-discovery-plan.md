# Decade Templates & MusicKit Discovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve FM prompt accuracy with decade language and use MusicKit for current-decade subject discovery.

**Architecture:** Two changes to FoundationModelService (rewrite templates + add MusicKit branch in generateCultureMap) and one new method on MusicService. FoundationModelService gains an optional `musicService` property injected by ServiceManager.

**Tech Stack:** Swift 6, MusicKit, Apple Foundation Models

---

### Task 1: Decade-focused FM templates

**Files:**
- Modify: `anaspace/Services/AI/FoundationModelService.swift:135-212`

**Step 1: Add `decadeString(for:)` helper**

Add this private method after `cleanAnswer()` (after line ~204), before `fillTemplate()`:

```swift
/// Convert exact year to decade string: 1977 → "the 1970s"
private func decadeString(for year: Int) -> String {
    let decade = (year / 10) * 10
    return "the \(decade)s"
}
```

**Step 2: Update `fillTemplate()` to handle `{decade}`**

Replace the existing `fillTemplate` method at line ~207 with:

```swift
/// Fill template placeholders with actual values.
private func fillTemplate(_ template: String, subject: String, place: String, year: Int) -> String {
    template
        .replacingOccurrences(of: "{subject}", with: subject)
        .replacingOccurrences(of: "{place}", with: place)
        .replacingOccurrences(of: "{year}", with: String(year))
        .replacingOccurrences(of: "{decade}", with: decadeString(for: year))
}
```

**Step 3: Rewrite `entityQuestions` with harness-recommended templates**

Replace the `entityQuestions` array at lines ~135-144 with:

```swift
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
```

Note: These templates are simpler — most drop `{year}` entirely per harness findings. Only the subject question (built in `processObservation` and other callers) uses `{decade}`.

**Step 4: Update subject question in `processObservation()` to use decade language**

At line ~417, replace:
```swift
subjectQuestion = "Which music artist FROM \(location) was most popular in \(year)? Answer with just the name."
```
with:
```swift
subjectQuestion = "Name a famous \(decadeString(for: year)) musician from \(location)."
```

**Step 5: Update subject question in `processYearChange()` to use decade language**

At line ~442, replace:
```swift
let question = "Who is the music artist most connected to \(subject)'s legacy in \(location) in \(year)? Just the name."
```
with:
```swift
let question = "Name a famous \(decadeString(for: year)) musician from \(location)."
```

**Step 6: Build and verify**

Build with XcodeBuildMCP `build_sim` to confirm it compiles. No runtime test needed yet — we'll verify both tasks together.

**Step 7: Commit**

```
git add anaspace/Services/AI/FoundationModelService.swift
git commit -m "Rewrite FM templates with decade language per harness findings"
```

---

### Task 2: MusicKit-first subject discovery for 2010s+

**Files:**
- Modify: `anaspace/Services/Music/MusicService.swift` (add `discoverArtist(near:)`)
- Modify: `anaspace/Services/AI/FoundationModelService.swift` (add `musicService` property, branch in `generateCultureMap`)
- Modify: `anaspace/Services/ServiceManager.swift` (wire `musicService`)

**Step 1: Add `discoverArtist(near:)` to MusicService**

Add this method to `MusicService.swift`, after the existing `searchSongs` method (after line ~85):

```swift
/// Discover a prominent artist associated with a location by searching the MusicKit catalog.
/// Returns the top artist name, or nil if unavailable.
func discoverArtist(near location: String) async -> String? {
    guard isAuthorized else { return nil }

    do {
        var request = MusicCatalogSearchRequest(term: location, types: [Artist.self])
        request.limit = 5

        let response = try await request.response()
        guard let artist = response.artists.first else { return nil }

        print("[MusicKit] Discovered artist for \(location): \(artist.name)")
        return artist.name
    } catch {
        print("[MusicKit] Artist discovery failed: \(error)")
        return nil
    }
}
```

**Step 2: Add optional `musicService` property to FoundationModelService**

At the top of the class (after line ~13, after `preloadTask`), add:

```swift
/// Optional MusicKit service for current-decade artist discovery.
var musicService: MusicService?
```

**Step 3: Wire `musicService` in ServiceManager**

In `ServiceManager.swift`, find the `init()` method (or wherever services are configured). Add after `claude` and `music` are created:

```swift
claude.musicService = music
```

If there's no explicit init, add one or set it in an appropriate setup location. Check the file for the right place.

**Step 4: Add MusicKit branch in `generateCultureMap()`**

In `FoundationModelService.swift`, replace the Phase 1 subject resolution block (lines ~230-241) with:

```swift
// Phase 1: Resolve subject
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
```

**Step 5: Build and verify**

Build with XcodeBuildMCP `build_sim`. Then `build_run_sim` and test by:
1. Setting year picker to a historical decade (1970s) — should behave as before, FM-driven
2. Setting year picker to current decade (2020s) — should see `[FM] Phase 1 ... via MusicKit:` in logs

**Step 6: Commit**

```
git add anaspace/Services/Music/MusicService.swift anaspace/Services/AI/FoundationModelService.swift anaspace/Services/ServiceManager.swift
git commit -m "Add MusicKit-first subject discovery for 2010s+ decade"
```

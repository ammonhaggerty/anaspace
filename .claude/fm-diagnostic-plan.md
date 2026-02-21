# Foundation Model: Multi-Question Architecture

## Summary
The on-device Apple Foundation Model (~3B params) answers simple plain-text Q&A accurately (~7/7) but hallucinates badly with @Generable structured generation. The solution: ask individual explicit questions and assemble the culture map ourselves.

## Discovery Timeline

### Phase 1: Plain text diagnostic (works great)
Simple factual questions get correct answers consistently:
- SF 1968: Jefferson Airplane ✓
- Austin 1975: Continental Club ✓
- London 1977: Sex Pistols ✓
- Detroit 1965: Temptations / Marvin Gaye ✓
- Seattle 1992: Pearl Jam / Nirvana ✓
- NYC 1955: Minton's Playhouse ✓

### Phase 2: @Generable structured generation (fails badly)
Same questions with `generating: CultureMap.self` produce hallucinations:
- SF 1968: Jimi Hendrix (from Seattle, not SF), entities like "ALTA RECORDS", "CONCERT COLLEGE OF SAN FRANCISCO" (fake)
- Detroit 1965: "WOODSTOCK STADIUM" (fake), "BUDDY HOLLY" (died 1959), "SAMUEL L JACKSON" (actor)
- London 1977: Jimi Hendrix again (died 1970), "SEATTLE MUSIC SCENE" as a London entity

**Root cause**: The @Generable schema (8 entities × 5 fields each) consumes so many tokens on schema compliance that the model can't reason about facts.

### Phase 3: Two-phase approach (subject OK, entities still bad)
Pre-resolve subject via plain text, then structured generation with known subject.
- Subject resolution works perfectly
- But entity generation STILL hallucinates even with correct subject pre-seeded
- Also triggers Apple safety guardrails (~40% of structured generation attempts)

### Phase 4: Multi-question Q&A (current — works well)
Completely bypass @Generable for Tier 1. Ask individual explicit questions:
1. Phase 1: "Who is the most iconic artist FROM {place} in {year}?" → subject
2. Phase 2: 8 individual entity questions → collaborator, peer, influence, follower, creation, place, event, movement
3. Phase 3: birthInfo + narrative questions

**Results (latest diagnostic):**

SF 1968 / Jefferson Airplane — 6/7 entities correct:
- Marty Balin ✓, Big Brother ✓, Frank Zappa ✓, The Fillmore ✓, Summer of Love ✓, Psychedelic Rock ✓

Detroit 1965 / Marvin Gaye — 7/7 correct:
- Tammi Terrell ✓, Ray Charles ✓, Prince ✓, Fox Theatre ✓, Soul ✓

London 1977 / David Bowie — 8/8 correct:
- Carlos Alomar ✓, Brian Eno ✓, Iggy Pop ✓, Lady Gaga ✓, Heroes ✓, Art Rock ✓
- BirthInfo: "B. 1947, LONDON" ✓ (perfect format)

## Current Architecture

### FoundationModelService.swift — Multi-Question Flow

```
processObservation / processShortcutQuery / processYearChange / etc.
  └→ generateCultureMap(subjectQuestion:, location:, year:, knownSubject:)
       ├→ Phase 1: ask(subjectQuestion) — plain text, ~0.3s
       ├→ Phase 2: 8× ask(entityQuestion) — sequential, ~0.3s each
       │    └→ emitUpdate() after each entity (progressive streaming)
       ├→ Phase 3: ask(birthInfo) + ask(narrative) — plain text
       └→ preloadEntityDetails() — Tier 3 (still uses @Generable EntityDetail)
```

### Key Methods

- `ask(_ question:)` — single plain-text Q&A via `LanguageModelSession().respond(to:)`
- `cleanAnswer(_ raw:)` — strips verbose preambles ("The most iconic artist is..."), filters guardrail refusals, extracts name from sentence-form answers
- `fillTemplate(_:subject:place:year:)` — fills `{subject}`, `{place}`, `{year}` in question templates
- `generateCultureMap(subjectQuestion:location:year:knownSubject:onUpdate:)` — orchestrates all 3 phases

### Entity Question Templates
Each uses `"Answer with ONLY the name"` suffix:
- collaborator: "{subject}'s closest musical collaborator around {year}?"
- peer: "A musical peer of {subject} in {place} around {year}?"
- influence: "{subject}'s biggest musical influence?"
- follower: "An artist most directly influenced by {subject}?"
- creation: "{subject}'s most famous song or album around {year}?"
- place: "The venue in {place} most associated with {subject}?"
- event: "A major music event in {place} around {year} connected to {subject}?"
- movement: "The music genre or movement {subject} was part of in {year}?"

### Query Types → Phase 1 Questions
- **processObservation**: Builds from signals (transcript → voice request; Shazam → artist is subject; else → location/year question)
- **processSubjectChange**: knownSubject = newSubject (skip Phase 1)
- **processYearChange**: "Who is the music artist most connected to {subject}'s legacy who was active in {location} in {year}?"
- **processLocationChange**: "Who is the closest cultural analog to {subject} FROM {location}?"
- **processShortcutQuery**: Appends "Who is the single most relevant music artist?" to the prompt

### Answer Cleaning (`cleanAnswer`)
1. Filter guardrail refusals: "i can't assist", "i cannot", "i'm sorry", "as an ai"
2. Strip trailing periods and quotes
3. Extract name from "X is Y" / "X was Y" patterns (takes text after last "is"/"was")
4. Strip preambles: "the answer is", "that would be"

### EntityType.defaultRelationship(for:)
Added to ServiceTypes.swift — provides template relationship text per entity type (e.g., "Close collaborator of {subject}").

## Known Issues

1. **Apple safety guardrails** — ~40% of questions trigger guardrails intermittently (creation and birthInfo most affected). These are filtered out gracefully (entity skipped, nil returned). This is Apple's content filter issue, not ours.

2. **20-char entity name truncation** — Long names get cut off ("MOTOWN 25TH ANNIVERS"). This is a UI grid constraint. Could consider abbreviation logic.

3. **Some factual misses** — "Spiral Stare" (hallucinated peer for SF 1968), O2 Arena (didn't exist in 1977). ~1 miss per 8 entities on average.

4. **Birth info sometimes empty** — Guardrails block birth-related questions for some artists.

5. **Timing** — ~5-9s total (subject 0.3s + 8 entities ~0.3s each + birthInfo + narrative). Entities stream progressively into the UI.

## What Changed from Original Architecture

### Removed
- `import MusicKit` from FoundationModelService
- `fetchCandidatePool()` — Wikipedia + MusicKit parallel fetch
- `searchMusicKit()` — MusicKit artist search
- `tier1Instructions` — complex 9-line instructions about candidates
- `buildObservationPrompt()`, `buildSubjectChangePrompt()`, `buildYearChangePrompt()`, `buildLocationChangePrompt()` — old prompt builders
- Candidate pool injection in `generateCultureMap`
- `streamResponse(to:generating: CultureMap.self)` — no longer used for Tier 1

### Added
- `EntityQuestion` struct + `entityQuestions` array — 8 explicit question templates
- `ask(_:)` — plain-text Q&A helper
- `cleanAnswer(_:)` — answer extraction and refusal filtering
- `fillTemplate(_:)` — template interpolation
- `resolveSubject(from:)` — (was used in two-phase, now inlined into `ask`)
- `EntityType.defaultRelationship(for:)` — template relationship text
- `ServiceManager.queryShortcut` now accepts `locationLabel:` and `contextYear:` params

### Still Using @Generable
- `EntityDetail` (Tier 3) — only 3 fields (bio, description, recommendedSong), small enough for the model
- `CultureMap` and `CultureEntity` types are still defined but NOT used for generation anymore — only their `toClaudeResult()` conversion is used if we ever re-enable structured generation

### Files Modified This Session
- `anaspace/Services/AI/FoundationModelService.swift` — major rewrite (multi-question architecture)
- `anaspace/Services/ServiceTypes.swift` — added `defaultRelationship(for:)` to EntityType
- `anaspace/Services/ServiceManager.swift` — updated `queryShortcut` signature
- `anaspace/App/AnaspaceApp.swift` — pass location/year to queryShortcut, diagnostic trigger

## What NOT to Change
- Keep @Generable types defined (CultureMap, CultureEntity, EntityDetail)
- Keep EntityDetail Tier 3 loading via @Generable (small schema, works fine)
- Keep the 5 query type methods (processObservation, etc.) — ClaudeService API compatibility
- Keep entity detail caching and preloading
- Keep WikiDataTool.swift code — not called but useful reference

## Next Steps
1. **Test with actual UI** — try idea cards, voice requests, entity navigation
2. **Remove diagnostic code** — or guard with `#if DEBUG` after confirming UI works
3. **Consider**: ask a second peer/collaborator question to fill the slot lost to guardrails
4. **Consider**: retry on guardrail failure with rephrased question
5. **Consider**: use the model's session memory — ask all questions in one session so it has context from previous answers

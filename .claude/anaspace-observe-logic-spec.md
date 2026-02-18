# Anaspace — Observe Logic & Decision Spec

## Purpose

This document defines the internal logic flow of the observe system — from button press through service activation, signal processing, decision routing, and triad assembly. It is the technical companion to the Observe Interaction Spec (which defines gesture mechanics, haptics, and UX) and serves as the primary reference for implementation.

The output of every observation is a **culture map** anchored to three dimensions: **Subject**, **Place**, and **Time**. This document describes how those three values are determined from multimodal input signals.

---

## Constraints & Ground Rules

1. **No text input.** The only way to influence the culture map is to speak or sing while the system is observing. There is no search bar, no keyboard, no typing.

2. **No voice output.** The app never speaks, never reads aloud, has no chat personality. All output is visual (the culture map rendered on the character grid) and haptic.

3. **Defaults are "here" and "now."** Time defaults to the current moment. Place defaults to the user's current GPS location. These defaults hold unless explicitly overridden by a voice prompt or by the subject's own context (e.g., Shazam identifies a song from 1971 → Time shifts to 1971).

4. **Subject is inferred, not declared** (in most cases). The subject comes from what the system hears (a song, lyrics) or what the user speaks ("Observe Henry Miller"). It can be any cultural entity: a musician, artist, author, filmmaker, designer, movement, genre, place, work, or era.

5. **Everything is cultural context.** The system frames all exploration through the lens of cultural connections — music, art, history, influence, place, time. It is not a general-purpose assistant. Voice prompts that fall outside this domain are gracefully deflected.

6. **The triad is always complete.** Every observation must resolve to a Subject + Place + Time. If any dimension is weak or missing, the system fills it using defaults, inference, or the resolution cascade described below.

---

## Service Inventory

These are the services involved in an observation, listed with their roles and activation timing.

| Service | Role | Activation | Runs On |
|---------|------|------------|---------|
| **CoreLocation** | Captures GPS coordinates, resolves to place name | Immediately on button press | Device |
| **AVAudioEngine** | Captures raw audio stream, feeds all audio consumers | Immediately on button press | Device |
| **ShazamKit** | Identifies recorded music from audio fingerprint | Immediately on button press (parallel) | Device + Network |
| **Apple Sound Analysis** | Classifies audio scene (music/speech/silence/etc.) | Immediately on button press (parallel) | Device |
| **Apple Speech Recognition** | Transcribes speech to text (on-device) | Immediately on button press (parallel) | Device |
| **Haptic Engine** | Communicates system state to user via vibration patterns | Immediately on button press | Device |
| **Apple Music / MusicKit** | Enriches Shazam results with metadata (genre, album, editorial notes, Apple Music ID) | After Shazam match (sequential) | Device + Network |
| **Claude** | Interprets voice prompts, resolves ambiguity, finds analogs, generates culture map, identifies songs from lyrics | After observation resolves (sequential) | Network |

### What's NOT in the Pipeline

- **Speech synthesis / text-to-speech** — The app never talks. No voice output of any kind.
- **Wikidata** — Claude's training data contains sufficient cultural knowledge for the connections we need. Adding Wikidata as a structured data source introduces pipeline complexity without clear benefit at this stage. Can be revisited if Claude's knowledge proves insufficient for specific structured lookups (precise dates, discographies, etc.).
- **Apple Intelligence / on-device LLM** — Deferred. Claude handles all intelligence tasks for v1.

### A Note on Speech Recognition

Apple Speech Recognition (`SFSpeechRecognizer`) runs on-device and provides real-time transcription. It serves a specific role in this pipeline: converting the user's spoken words into text so that Claude can interpret the intent. Claude never receives raw audio — it receives the transcribed text as part of the assembled context package.

This keeps Claude focused on cultural intelligence (what it's good at) rather than audio transcription (which Apple handles for free, locally, instantly). It also means the transcription step works without network access.

Speech Recognition runs in parallel with everything else from the moment the button is pressed. It doesn't add latency. If the user doesn't speak, it produces nothing and is ignored.

### Activation Groups

**Group 1 — Immediate (on button press, all parallel):**
- CoreLocation
- AVAudioEngine
- ShazamKit
- Apple Sound Analysis
- Apple Speech Recognition
- Haptic Engine

**Group 2 — Chained (after observation resolves, sequential):**
- MusicKit (if Shazam matched → enrich with metadata)
- Claude (receives assembled context package → builds culture map)

The boundary between Group 1 and Group 2 is the **resolution moment** — when the observation phase ends and assembly begins.

---

## The Two Paths

### Path A: Tap Observe ("Listen to my world")

**Gesture:** User taps and releases within 500ms.

**Meaning:** "Observe my environment." The system listens to whatever is happening — music, ambient sound, singing, silence — and uses it plus the user's location to build a culture map.

**Duration:** System-controlled. Runs until a resolution trigger fires, up to 10-second hard timeout.

```
User taps button (< 500ms press)
│
├─ All Group 1 services activate in parallel
│
├─ Sound classifier produces scene type (~1 second)
│  ├─ music          → haptic shifts to 2 Hz
│  ├─ speech         → haptic shifts to da-dum pattern
│  ├─ music+speech   → haptic shifts to 2 Hz
│  ├─ singing        → haptic stays at 1 Hz (ambiguous)
│  ├─ silence        → haptic slows to 0.5 Hz
│  └─ ambient        → haptic slows to 0.5 Hz
│
├─ Observation runs until resolution trigger:
│  ├─ Shazam match (3–8s typical)       → success haptic, resolve
│  ├─ Silence for 5 continuous seconds  → timeout haptic, resolve
│  └─ Hard timeout at 10 seconds        → timeout haptic, resolve
│
└─ On resolution → collect all signals → enter Assembly phase
```

**Note on speech during tap mode:** If someone speaks during a tap observation (e.g., saying "who influenced this?" over music), Speech Recognition captures it as a bonus signal. The user doesn't need to use hold mode to speak — hold mode is specifically for when the user wants to *only* speak, controlling the duration themselves. Tap mode captures everything.

### Path B: Press and Hold ("Listen to me")

**Gesture:** User presses and holds beyond 500ms.

**Meaning:** "I'm giving you input." The system is observing for as long as the user holds the button — like a walkie-talkie. All the same services run (Shazam may catch background music), but the user is signaling that their voice is the primary input.

**Duration:** User-controlled. Runs for as long as the button is held. Resolves on release.

```
User presses and holds button (≥ 500ms)
│
├─ All Group 1 services activate in parallel on initial press
│  (Shazam runs — may catch music playing in the background)
│  (Speech Recognition captures spoken words in real-time)
│  (Sound Analysis classifies the scene)
│
├─ At ~500ms, system determines this is a hold
│  └─ Haptic shifts to speech-texture pattern (if speech detected)
│
├─ User continues holding and speaking
│  (All services continue running for the duration)
│
├─ User releases button
│  ├─ Hold release haptic fires
│  ├─ All services stop capturing
│  └─ System collects whatever signals were gathered
│
└─ Collect all signals → enter Assembly phase
```

**What "observing while holding" means in practice:** The hold doesn't change *what* services run — it changes *who controls the duration*. In tap mode, the system decides when to resolve (Shazam match, silence timeout, hard timeout). In hold mode, the user decides. Everything else is identical. If the user holds and says nothing in a silent room, the system resolves with location only. If they hold while music plays, Shazam may match. If they speak, Speech Recognition captures it. The system takes whatever context it has at the moment of release.

### Gesture Detection

Both paths begin identically. On button press, all Group 1 services activate immediately. The system doesn't wait to determine tap vs. hold before starting — it starts everything, then at 500ms determines which mode governs the session.

| Press duration | Mode | Duration control | Resolution trigger |
|---------------|------|-----------------|-------------------|
| < 500ms | Tap (observe) | System-controlled | Shazam match, silence timeout, or hard timeout |
| ≥ 500ms | Hold (walkie-talkie) | User-controlled | Button release |

If the user intended a tap but held slightly past 500ms, the system is already running all services, so the hold mode simply means "keep going until you let go." No time is lost.

---

## Signal Collection

At the resolution moment, the system has collected up to five raw signals. Any or all may be empty.

| Signal | Source | Content | Example |
|--------|--------|---------|---------|
| `shazamResult` | ShazamKit | Song title, artist, album, Apple Music ID | "Family Affair" by Sly & The Family Stone |
| `transcript` | Apple Speech Recognition | Raw text of any speech detected | "who influenced this artist" |
| `audioScene` | Sound Analysis | Scene classification enum | `.music`, `.speech`, `.musicAndSpeech` |
| `location` | CoreLocation | Coordinates + resolved place name | 37.8044° N, 122.2712° W → "Oakland, CA" |
| `timestamp` | System clock | Current date and time | 2025-06-14T14:30:00Z |

---

## Decision Router

The Decision Router evaluates the collected signals and determines which **assembly path** to follow. This is the core branching logic of the system.

### Step 1: Classify the Transcript

If a transcript exists, classify it as one of three types:

**Command** — An instruction directed at the app.
- Characteristics: short (< 20 words), contains imperative verbs or navigation language, references cultural domain concepts, parses as a grammatical sentence
- Examples: "Show me the jazz scene here in the 1960s", "Observe Henry Miller", "Who influenced this artist?", "Go to Berlin", "Explore punk in 1977"
- Subtype — **Query**: A question about the current or incoming subject ("who influenced this?", "what was happening here in the 70s?")
- Subtype — **Navigation**: A directive to set one or more triad dimensions ("Observe Henry Miller in 1965 in Big Sur", "Go to Tokyo", "Show me the 1920s")
- Subtype — **Subject declaration**: Explicitly names a cultural entity as the focus ("Observe Frida Kahlo", "Show me Bauhaus")

**Lyrics** — Fragments of a song the user is singing or reciting.
- Characteristics: longer, poetic/abstract, repetitive phrases, non-imperative, doesn't parse as an instruction
- Examples: "I want to take you higher", "There's a riot going on", "Blue moon, you saw me standing alone"

**Ambiguous** — Could be either. System cannot determine with confidence.
- Route to Claude for disambiguation at assembly time.

**Classification method:** This classification can be handled with heuristics for clear cases (short imperative sentence = command; long poetic text = lyrics) and Claude for ambiguous cases. The heuristic layer saves a Claude call for the majority of interactions.

### Step 2: Route to Assembly Path

The router evaluates the combination of signals present and selects an assembly path:

```
HAS SHAZAM RESULT?
├─ YES
│  ├─ HAS TRANSCRIPT?
│  │  ├─ YES, classified as COMMAND
│  │  │  └─ Path: MUSIC + COMMAND
│  │  │     (Shazam sets subject, transcript modifies the inquiry)
│  │  ├─ YES, classified as LYRICS
│  │  │  └─ Path: MUSIC ONLY
│  │  │     (Shazam matched the song; discard redundant lyrics)
│  │  └─ YES, classified as AMBIGUOUS
│  │     └─ Path: MUSIC + COMMAND
│  │        (Shazam has the song; treat transcript as potential command, let Claude sort it out)
│  └─ NO TRANSCRIPT
│     └─ Path: MUSIC ONLY
│        (Pure Shazam identification)
│
└─ NO
   ├─ HAS TRANSCRIPT?
   │  ├─ YES, classified as COMMAND
   │  │  └─ Path: VOICE COMMAND
   │  │     (User spoke an instruction; no music context)
   │  ├─ YES, classified as LYRICS
   │  │  └─ Path: LYRIC IDENTIFICATION
   │  │     (User sang/recited; attempt song identification via Claude)
   │  └─ YES, classified as AMBIGUOUS
   │     └─ Path: VOICE COMMAND (with lyric fallback)
   │        (Try as command first; if Claude can't parse it as an instruction, try as lyrics)
   │
   └─ NO TRANSCRIPT
      └─ Path: LOCATION ONLY
         (Silent observation; explore based on place and time)
```

---

## Assembly Paths (Detailed)

Each assembly path describes how the raw signals are transformed into a complete triad (Subject + Place + Time) and what instructions are passed to Claude.

### Path: MUSIC ONLY

**Trigger:** Shazam matched a song, no meaningful speech detected.

**Triad assembly:**
- **Subject** = Artist from Shazam result (primary). Song and album are secondary context.
- **Place** = User's current location (default: "here").
- **Time** = Song's release year from Shazam/MusicKit metadata.

**Service chain:**
1. Shazam result → MusicKit enrichment (genre, album, editorial notes, release year)
2. Location → reverse geocode to place name
3. All data → Claude: "The user heard [song] by [artist] ([year]) at [location]. Build the culture map exploring the connections between this artist, this place, and this era."

**Note on Time:** The release year of the song becomes the time anchor, NOT the current year. The user is hearing a song from 1971 — the interesting exploration is 1971, not 2025. The user can always shift time later via voice command.

### Path: MUSIC + COMMAND

**Trigger:** Shazam matched a song AND the user spoke a command over the music.

**Triad assembly depends on command type:**

**If query** ("who influenced this artist?", "what was happening here when this came out?"):
- **Subject** = Artist from Shazam (unchanged)
- **Place** = Current location (unchanged)
- **Time** = Song's release year (unchanged)
- The query modifies what Claude *does* with the triad, not the triad itself.
- Claude instruction: "The user heard [song] by [artist] ([year]) at [location] and asked: '[transcript]'. Answer the question in the context of this cultural intersection."

**If navigation with partial override** ("show me this in Berlin", "go to the 1920s"):
- Override only the dimensions mentioned. Keep the rest from Shazam/location.
- "Show me this in Berlin" → Subject stays (artist), Place shifts to Berlin, Time stays (release year)
- "Go to the 1920s" → Subject stays (artist — or finds the analog for that artist in the 1920s), Place stays, Time shifts to 1920s
- Claude instruction includes the override: "The user heard [song] by [artist]. They want to explore [override dimension]. Find the appropriate analog if needed."

**If subject declaration over music** ("Observe the producer", "show me the label"):
- This is a pivot. The user is redirecting away from the performing artist.
- Subject shifts to whatever they named. Place and Time stay.
- "Observe the producer" → Claude resolves who produced the identified song → that person becomes the subject.

### Path: VOICE COMMAND

**Trigger:** No Shazam match. User spoke a command (hold mode, or speech detected during tap).

**Triad assembly depends on what's specified in the command:**

The command is parsed for explicit triad dimension values:

| Spoken element | Triad dimension | Example |
|---------------|----------------|---------|
| Cultural entity name | Subject | "Observe Henry Miller" → Subject = Henry Miller |
| Place name | Place | "in Big Sur" → Place = Big Sur |
| Year/decade/era | Time | "in 1965" → Time = 1965 |

**Rules:**
- Any dimension NOT specified in the command defaults:
  - Subject → **required** — if no subject is named, the command is treated as a place/time navigation on the current subject (if one exists), or the system uses the location cascade to find a subject.
  - Place → current GPS location ("here")
  - Time → current year ("now")
- All three CAN be specified: "Observe Henry Miller in 1965 in Big Sur" → Subject = Henry Miller, Place = Big Sur, Time = 1965.
- Two can be specified: "Observe Bauhaus in Berlin" → Subject = Bauhaus, Place = Berlin, Time = now.
- One can be specified: "Observe Frida Kahlo" → Subject = Frida Kahlo, Place = here, Time = now.

**Parsing responsibility:** Claude handles the parsing. The system sends the raw transcript plus the current defaults (location, time) and Claude returns the resolved triad values. This is more reliable than regex/NLP for natural language like "show me what punk looked like in London before the Sex Pistols."

**Service chain:**
1. Transcript + location + timestamp → Claude: "Parse this voice command into a triad. The user is at [location] and the current time is [now]. Extract Subject, Place, and Time from their instruction. Use defaults for any unspecified dimension. Then build the culture map."
2. Claude returns the resolved triad + culture map in a single response.

**Note:** For straightforward commands, this can be a single Claude call — parse and build in one pass. Only if the command is highly ambiguous would a separate parse-then-build flow be needed, and even then Claude can handle both in one structured response.

### Path: LYRIC IDENTIFICATION

**Trigger:** No Shazam match. Transcript classified as lyrics (user was singing/humming).

**Triad assembly:**
- **Subject** = Unknown — needs identification
- **Place** = Current location (default)
- **Time** = Will be set once the song is identified

**Service chain:**
1. Transcript → Claude: "The user sang or recited these words: '[transcript]'. This appears to be song lyrics. Identify the most likely song, artist, and release year. Then build the culture map for that artist at the user's location [location] anchored to the song's era."
2. If Claude identifies the song → culture map is built around the identified artist
3. If Claude identifies the song → additionally chain to MusicKit to enrich (search by song title + artist for Apple Music ID, genre data)
4. If Claude cannot confidently identify → fall back to LOCATION ONLY path, optionally surfacing Claude's best guesses

**User experience note:** The observation phase closes on its normal trigger (timeout or release). The lyric identification happens during the post-observation processing phase (1–3 seconds). The user feels the observation complete (terminal haptic), then sees a brief processing state before the culture map appears — or, if identification fails, a location-based result.

### Path: LOCATION ONLY

**Trigger:** No Shazam match, no meaningful transcript. Silent observation or all other paths exhausted.

**Triad assembly:**
- **Subject** = Determined by location cascade (see below)
- **Place** = Current location
- **Time** = Current date/time (with potential historical anchoring)

**Location resolution cascade:**

The system asks Claude to find culturally significant entities connected to the user's location, with instructions to search at expanding scope until something interesting surfaces:

1. **Exact coordinates** — Is the user at or very near a notable cultural site? (Landmark, venue, studio, birthplace of a notable figure.)
2. **Neighborhood/district** — Cultural associations with the immediate area. (e.g., Haight-Ashbury → counterculture, Harlem → jazz/renaissance)
3. **City** — The city's strongest cultural associations. Most observations resolve here. (e.g., Oakland → Black Panther movement, funk, hyphy)
4. **Metro area / Region** — Broader cultural geography. (e.g., Bay Area → tech culture, counterculture, psychedelic rock)
5. **Time anchor** — If location is culturally thin at all levels, lean on the time dimension: what happened on this date in cultural history? What was significant this week/month in [nearest interesting year]?
6. **User affinity** — If the user has exploration history, surface something connected to their demonstrated interests, loosely anchored to the available location/time.

**The principle: no observation ever returns empty.** The cascade guarantees a result. The quality of the result depends on how culturally rich the location is, but there is always *something*.

**Service chain:**
1. Location (with full reverse geocode: coordinates, neighborhood, city, region) + timestamp → Claude: "The user is at [full location details] at [current date/time]. No audio context was captured. Find the most culturally significant entity connected to this place and build a culture map. Search at expanding scope: exact site, neighborhood, city, region. Use the current date as a time anchor if the location itself is culturally thin. Return a complete culture map with subject, place, time, and connections."
2. Claude returns the culture map.

---

## Triad Defaults & Overrides Summary

| Dimension | Default | Set by Shazam | Set by Voice | Precedence |
|-----------|---------|---------------|--------------|------------|
| **Subject** | Location cascade | Artist from matched song | Named entity in command | Voice > Shazam > Location cascade |
| **Place** | Current GPS ("here") | — (Shazam doesn't set place) | Named place in command | Voice > GPS |
| **Time** | Current year ("now") | Song release year | Named year/era in command | Voice > Shazam > Now |

**Precedence rules:**
- Voice commands always win. If the user says "Observe Kraftwerk" while Sly Stone is playing, the subject is Kraftwerk, not Sly Stone.
- Shazam overrides defaults but not voice. If music is playing and the user says nothing, Shazam sets the subject and time. If the user speaks over the music, their words take priority for whatever dimensions they specify.
- Unspecified dimensions fall to the next level. "Observe Kraftwerk" over music playing → Subject = Kraftwerk (voice), Place = here (default), Time = now (default) — the Shazam result is available as context but doesn't drive the triad.

---

## Post-Assembly: What Claude Receives

After the Decision Router selects a path and signals are collected, Claude receives a structured prompt. The exact prompt format will be defined in a separate prompt design spec, but the data package always includes:

```
{
  // The resolved triad (or raw inputs for Claude to resolve)
  subject: {
    name: "Sly Stone",              // null if Claude needs to determine
    type: "person",                 // person | work | genre | movement | place | era | null
    source: "shazam",              // shazam | voice_command | lyric_identification | location_cascade
    context: {                      // Additional context from the source
      song: "Family Affair",
      album: "There's a Riot Goin' On",
      appleMusicID: "...",
      genre: "Funk/Soul",
      releaseYear: 1971
    }
  },
  place: {
    name: "Oakland, CA",
    neighborhood: "Temescal",
    coordinates: { lat: 37.8044, lng: -122.2712 },
    source: "gps",                  // gps | voice_command
  },
  time: {
    year: 1971,
    source: "shazam_metadata",      // shazam_metadata | voice_command | current
  },

  // MusicKit enrichment (if Shazam matched)
  musickit: {
    editorialNotes: "...",
    genre: "Funk/Soul",
    relatedArtists: [...],
    appleMusicURL: "..."
  },

  // The user's voice input (if any)
  voice_input: {
    transcript: "who influenced this sound?",
    type: "query",                  // query | navigation | subject_declaration | lyrics | none
  },

  // Session context
  session: {
    previous_subject: null,         // If continuing, what was the last subject?
    user_affinities: { ... },       // Genre/era/category weights from exploration history
    observation_duration: 5.2,
    resolution_trigger: "shazam_match",
    gesture_mode: "tap"             // tap | hold
  }
}
```

**What Claude returns:**
1. The **culture map** — a structured graph of related entities with typed relationships (influences, collaborators, contemporaries, movements, places, works)
2. A **narrative sentence** — one evocative sentence connecting the subject to the place and time
3. **Navigation suggestions** — other subjects, places, or times the user might explore from here
4. If a voice query was asked — the **answer** to that query, grounded in cultural context

---

## Edge Cases in Decision Routing

### Voice command with no recognizable subject

**"Show me what was happening here in the 1960s"**
- No subject specified. Place = here, Time = 1960s.
- Claude determines the subject using the location cascade scoped to the 1960s: "What was culturally significant at [location] in the 1960s?"

### Voice command outside cultural domain

**"What's the weather like?"**
- The system recognizes this is out of scope.
- Claude responds with cultural context instead — no error message, no "I can't do that." The system simply finds the most interesting cultural angle on the current context and presents that. The culture map is the only output; there is no conversational response channel.
- If nothing can be built from the input, the system falls back to LOCATION ONLY.

### Voice command that's a question about the current subject

**"Tell me more about this" (while a culture map is displayed)**
- This is a query on the existing triad, not a new observation.
- Subject, Place, and Time stay the same.
- Claude receives the existing triad + "tell me more" and deepens the exploration.

### Shazam matches but the song/artist is obscure

- If Shazam returns a match but the artist has very little documented cultural history, the culture map may be thin.
- In this case, Claude should pivot to the *genre* or *movement* the artist belongs to, using the genre as the functional subject while keeping the artist as the nominal focus.
- The artist remains the entry point but the connections fan out through the genre's broader cultural web.

### Conflicting Shazam and voice signals

**Music playing: jazz. User says: "Observe punk rock."**
- Voice wins. Subject = punk rock (the genre).
- Shazam result is available in the context package but doesn't drive the triad.
- Claude may reference the contrast if it adds cultural value, or simply pivot cleanly.

### User re-observes while a culture map is displayed

- New observation completely replaces the current map.
- Previous triad becomes `session.previous_subject` for continuity context.
- No confirmation prompt — the observe action is fast and reversible through history.

### Hold mode with no speech and no music

- User holds the button in silence, then releases.
- System has: location + timestamp + nothing else.
- Routes to LOCATION ONLY path.
- This is expected behavior — the user may have intended to speak but changed their mind, or may be exploring the hold gesture. The system handles it gracefully.

### Hold mode catches unexpected music

- User holds to speak, but music is playing in the background.
- Shazam may match the background music during the hold.
- If the user also spoke a command, voice takes precedence (the Shazam result is supplementary context).
- If the user held but said nothing, the Shazam match becomes the primary signal — routes to MUSIC ONLY path.

---

## Service Dependency Map

This shows which services depend on which, and where parallelism is possible vs. where sequencing is required.

```
BUTTON PRESS (t=0)
│
├─── CoreLocation ──────────────────────────────────────┐
├─── AVAudioEngine ─┬── ShazamKit ──────────────────────┤
│                   ├── Apple Sound Analysis ────────────┤
│                   └── Apple Speech Recognition ────────┤
├─── Haptic Engine (continuous, driven by Sound Analysis)│
│                                                        │
▼ RESOLUTION (varies by mode)                            │
│  Tap: Shazam match / silence timeout / hard timeout    │
│  Hold: button release                                  │
│                                                        │
├─── Decision Router (evaluates all signals) ◄───────────┘
│    │
│    ├─── Transcript Classification (heuristic)
│    │
│    ▼
│    Assembly Path Selected
│    │
│    ├─── [if Shazam matched] ──► MusicKit Enrichment ───┐
│    │                                                    │
│    ▼                                                    ▼
│    Claude: Build Culture Map ◄──────────────────────────┘
│    (single call for most paths;                  
│     parses voice commands + builds map together) 
│         │
│         ▼
│    CULTURE MAP OUTPUT
│    (Subject + Place + Time + connections + narrative)
```

---

## Configurable Parameters (Decision Logic)

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| `holdThresholdMs` | 500 | 300–800 | Tap vs. hold gesture boundary |
| `hardTimeoutSeconds` | 10 | 5–15 | Maximum observation duration (tap mode) |
| `silenceTimeoutSeconds` | 5 | 3–8 | Auto-resolve after continuous silence (tap mode) |
| `shazamConfidenceThreshold` | 0.7 | 0.5–0.9 | Minimum Shazam confidence to accept a match |
| `speechConfidenceThreshold` | 0.4 | 0.2–0.7 | Minimum speech transcript quality to use |
| `commandMaxWords` | 20 | 10–30 | Transcripts longer than this lean toward lyrics classification |
| `discardShortTranscripts` | 3 | 2–5 | Transcripts shorter than this many words are discarded |
| `locationCascadeMaxLevel` | 4 | 1–6 | How far to expand location search (1=exact … 6=user affinity) |
| `voiceOverridesShazam` | true | — | Whether voice commands take precedence over Shazam results |
| `lyricIdEnabled` | true | — | Whether to attempt song identification from sung lyrics |

---

## What This Spec Does NOT Cover

- **Observe animation and visual feedback** — See `anaspace-observe-animation-spec.md`
- **Haptic patterns and gesture UX** — See `anaspace-observe-interaction-spec.md`
- **Rendering system and character grid** — See `anaspace-rendering-system.md`
- **Triad navigation and analog-finding** — See `anaspace-core-concepts.md`
- **Claude prompt design** — The exact prompts for each assembly path are a separate spec. This document defines *what* Claude receives and *what* it should return, not the specific prompt wording.
- **Culture map data structure** — The format of the culture map output (entities, relationships, graph structure) is defined with the rendering system.
- **Personalization and affinity model** — How user history influences subject selection is a layer on top of this logic.
- **Onboarding and permissions** — This document assumes all permissions (microphone, location, Apple Music) have been granted.

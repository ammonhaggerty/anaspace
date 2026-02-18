# Anaspace — Observe Interaction Spec

## Purpose

This document defines the complete behavior of the "observe" interaction — the primary entry point for all cultural exploration in Anaspace. It covers gesture mechanics, audio pipeline architecture, routing logic, haptic feedback language, resolution handling, and edge cases. This spec is independent from the rendering system and core concept documents; it describes *what happens* when the user initiates an observation and how the system assembles context from multimodal signals.

---

## Design Philosophy

The observe button is the only way to initiate new exploration. There is no text input, no search bar, no browsing interface. The user either listens to the world or speaks to the app. Everything flows from this single interaction point.

The system's job is to extract maximum context from a brief audio window and the user's location, then assemble that context into a structured package for the intelligence layer. The user should never need to tell the system *how* to listen — only *that* they want it to listen.

---

## Gesture Model

Two gestures on a single button. Zero ambiguity about user intent.

### Tap (tap and release immediately)

**Meaning:** "Listen to my world."

The app opens its ears to the environment. It captures whatever is happening — music playing, ambient sound, silence. The user is not providing input; they're asking the app to observe.

**Duration:** Runs until resolution or 10-second timeout, whichever comes first.

### Tap and Hold (press, hold, release)

**Meaning:** "Listen to me."

The user is speaking a command or instruction. The interaction is explicitly voice input. The hold duration is user-controlled — audio capture runs for as long as the button is held.

**Duration:** Runs until the user releases the button. No timeout while held. After release, a brief processing window (1–2 seconds) before resolution.

### Gesture Detection

The system distinguishes tap from hold based on a duration threshold:

- **< 300ms press duration:** Treated as a tap. Observe mode begins on release.
- **≥ 300ms press duration:** Treated as a hold. Voice capture mode is active while held.

Note: In both cases, audio capture and Shazam begin immediately on press — the 300ms threshold only determines which interaction *mode* governs the session. If the user intended a tap but held slightly long, the system is already running Shazam, so no time is lost.

---

## Audio Pipeline Architecture

### The Parallel Pipeline

The core architectural principle: **nothing waits for classification.** The moment observe is pressed, all audio consumers start simultaneously. Routing decisions happen after the fact, not before.

**On button press, these systems activate in parallel:**

1. **Shazam (ShazamKit)** — Receives raw audio immediately. Begins matching from frame one. No delay, no preprocessing.

2. **Local Sound Classifier (Apple Sound Analysis / `SNClassifySoundRequest`)** — Runs on-device. Classifies the audio scene: music, speech, both, or silence. Produces a classification signal within ~1 second.

3. **Speech Recognition (Apple Speech framework)** — Transcribes any detected speech. Runs continuously for the duration of the observation. Good at isolating voice from background music.

4. **Audio Buffer** — A rolling buffer captures the full raw audio stream. This buffer is available if any system needs to reprocess audio or if a late-starting consumer needs earlier frames.

5. **Location Capture (CoreLocation)** — Fires once on button press. Essentially instant. Captures GPS coordinates and resolves to a place name.

### Why Parallel, Not Sequential

The instinct to route audio — "figure out what's happening, then send it to the right system" — adds latency that directly harms the user experience. Shazam recognition can take 5–10 seconds; every second of routing delay is a second added to total wait time.

More importantly, the audio consumers are extracting *orthogonal information* from the same signal:
- Shazam wants the music fingerprint
- Speech Recognition wants the voice content
- Sound Classification wants the scene type

They don't compete. Let them all run.

### Classification Signal

The local sound classifier produces a scene classification within ~1 second of audio:

| Classification | Meaning |
|---------------|---------|
| `music` | Recorded music detected, no significant speech |
| `speech` | Voice detected, no significant music |
| `music+speech` | Both music and voice present |
| `silence` | No significant audio content |
| `ambient` | Environmental sounds but no music or speech |
| `singing` | Vocal content that resembles singing rather than speech |

This classification doesn't *route* audio (everything is already running). It drives two things:
1. **Haptic feedback** — the user feels what the app is detecting
2. **Resolution strategy** — determines how to assemble the final context package

---

## Scenario Handling

### Scenario 1: Music Playing, No Speech (Tap)

**The common case.** User is in a café, hears a song, taps observe.

1. Button press → all systems activate
2. ~1s: Sound classifier reports `music` → haptic shifts to 2 Hz
3. Shazam works on matching
4. Shazam resolves (typically 3–8 seconds) → success haptic
5. Observation closes early (no need to wait for timeout)
6. **Assembly:** Shazam result (song, artist, album) + location → intelligence layer

**If Shazam fails to match by 10s timeout:**
- Observation closes with timeout haptic
- Assembly uses location only, or any partial data Shazam returned
- System falls back to location-based exploration

### Scenario 2: Silence / Ambient (Tap)

**User observes in a quiet environment.** No music, no speech.

1. Button press → all systems activate
2. ~1s: Sound classifier reports `silence` or `ambient` → haptic slows to 0.5 Hz
3. By ~5 seconds, if still silence, the system can auto-resolve early (configurable; don't force the user to wait 10 seconds for nothing)
4. Resolution ramp haptic, then soft terminal haptic
5. **Assembly:** Location only → intelligence layer finds culturally significant entities for this place and current time

**Early termination for silence:** If the sound classifier reports silence/ambient for 5 consecutive seconds with no change, the system resolves. The threshold is configurable but 5 seconds balances responsiveness against the chance that music might start.

### Scenario 3: Speech Only — Tap and Hold

**User holds the button and speaks a command.** "Show me the jazz scene here in the 1960s."

1. Button press and hold → all systems activate (Shazam runs in background just in case)
2. ~1s: Sound classifier reports `speech` → speech-texture haptic begins
3. Speech Recognition transcribes in real-time
4. User releases button at ~3s
5. Brief processing pause, then resolution haptic
6. **Assembly:** Transcribed instruction + location → intelligence layer interprets the command and builds the triad

**Note:** Shazam runs during hold mode but will almost certainly return nothing (just a voice). This is fine — it costs nothing meaningful and covers the edge case where the user is speaking *and* music happens to be playing.

### Scenario 4: Music + Speech (Tap)

**The power-user case.** Music is playing, user taps observe and says "who influenced this artist?" over the music.

1. Button press → all systems activate
2. ~1s: Sound classifier reports `music+speech` → haptic shifts to 2 Hz (music detected)
3. Shazam processes the full audio stream (music fingerprint)
4. Speech Recognition isolates the voice and transcribes (Apple's speech framework handles background music well)
5. Shazam resolves → success haptic
6. **Assembly:** Shazam result + transcribed instruction + location → intelligence layer interprets "who influenced this artist" in context of the identified song

**Key insight:** The user does NOT need to use tap-and-hold for this scenario. A normal tap works because both Shazam and Speech Recognition run in parallel regardless. The speech is captured as a bonus signal. The tap-and-hold gesture is specifically for when the user wants to *only* speak, with no environmental audio to capture.

### Scenario 5: Someone Singing (Tap)

**Edge case.** User hums or sings a melody, hoping the app identifies the song.

1. Button press → all systems activate
2. ~1s: Sound classifier reports `singing` or ambiguous `speech`/`music`
3. Shazam tries to match the singing — may succeed for well-known songs with clear melody, but usually fails
4. Speech Recognition captures whatever lyrics/words are being vocalized
5. 10-second timeout reached, resolution ramp, soft terminal haptic
6. **Assembly:** No Shazam match + transcribed vocal content → system flags content as "possible lyrics" → intelligence layer (Claude) attempts song identification from lyric fragments

**Extended processing:** The observation window itself still closes at 10 seconds. The additional time for Claude to process lyrics is *post-observation processing*, not extended listening. The user sees/feels the observation complete, then the app shows a brief "identifying..." state while Claude works.

**Lyric vs. Command disambiguation:** After transcription, the system evaluates whether the captured text is an instruction or lyrics:
- **Commands** tend to be: short (< 15 words), use imperative verbs, parse as grammatical sentences, reference the app's domain ("show me," "explore," "go to")
- **Lyrics** tend to be: longer, more poetic/abstract, don't parse as instructions, may repeat phrases, use non-imperative language
- This classification happens at assembly time, not during capture. Claude handles ambiguous cases well.

### Scenario 6: Someone Singing — Tap and Hold

**Variant:** User holds the button and sings.

Same as Scenario 5, but the user explicitly signals "this is input from me" via the hold gesture. The system treats it as voice input initially, but when the transcript looks like lyrics rather than a command, it redirects to lyric identification.

This pathway is slightly better than Scenario 5 because the hold gesture gives the system a strong hint that the vocal content is intentional input (not just ambient sound), which can influence how aggressively it tries to identify the content as a song.

---

## Haptic Feedback Language

Haptics serve as a non-visual communication channel. The user should be able to keep the phone in their pocket, tap observe, and know from haptics alone what the app is detecting and when it resolves.

### Haptic Events

| Event | Pattern | Timing | Feel |
|-------|---------|--------|------|
| **Observe initiated** | Single strong tap | On button press | Crisp confirmation — "I heard you" |
| **Baseline listening** | Steady pulse | 1 Hz (1 pulse/second) | Calm heartbeat — "I'm active, processing" |
| **Music detected** | Doubled pulse | 2 Hz (2 pulses/second) | Excited — "I found something interesting" |
| **Nothing detected** | Slowed pulse | 0.5 Hz (1 pulse/2 seconds) | Patient — "It's quiet, but I'm still here" |
| **Speech detected** | Soft double-tap pattern | 1 Hz, da-dum rhythm | Distinct texture — "I hear you talking" |
| **Resolution ramp** | Accelerating pulses | Geometric: 1Hz → 2Hz → 4Hz → 8Hz over final 1 second | Building anticipation — "almost there" |
| **Success (Shazam match)** | Three quick taps | Rapid triplet | Triumph — "got it!" |
| **Timeout (no match)** | Long soft buzz | Single extended vibration | Gentle — "I tried, here's what I have" |
| **Hold release** | Brief double-tap | On finger release | Acknowledgment — "message received" |

### Haptic Transitions

Transitions between haptic states should be smooth, not abrupt:

- **Baseline → Music detected:** The pulse frequency ramps from 1 Hz to 2 Hz over ~0.5 seconds (not an instant jump)
- **Baseline → Nothing detected:** The pulse frequency ramps down from 1 Hz to 0.5 Hz over ~1 second
- **Any state → Resolution ramp:** The current pattern transitions into the accelerating sequence over the final 1 second before resolution

### Haptic Implementation Notes

- Use `UIImpactFeedbackGenerator` for regular pulses (medium intensity for baseline, light for slow states, heavy for success)
- Use `UINotificationFeedbackGenerator` for success (.success) and timeout (.warning)
- The resolution ramp uses progressively stronger impacts as frequency increases
- All haptic patterns should be cancellable — if the system resolves early, the ramp cuts short and jumps to the terminal haptic

---

## Resolution and Assembly

### What "Resolution" Means

Resolution is the moment the observation phase ends and the system has enough context to proceed. It is NOT the moment the user sees results — there may be a brief processing phase after resolution where the intelligence layer builds the triad.

### Resolution Triggers

The observation resolves when ANY of these conditions is met:

| Trigger | Typical Timing | Condition |
|---------|---------------|-----------|
| **Shazam match** | 3–8 seconds | Shazam returns a confident match |
| **Hold release** | User-controlled | User releases the button (hold mode only) |
| **Silence timeout** | ~5 seconds | Sound classifier reports silence/ambient for 5 continuous seconds |
| **Hard timeout** | 10 seconds | Maximum observation duration reached |

### The Context Package

When observation resolves, the system assembles a structured context package from all available signals. Not all fields will be populated in every scenario.

```
ContextPackage {
  // From Shazam (if matched)
  song: String?           // "Family Affair"
  artist: String?         // "Sly & The Family Stone"
  album: String?          // "There's a Riot Goin' On"
  genre: String?          // "Funk/Soul"
  releaseYear: Int?       // 1971
  appleMusicID: String?   // For MusicKit integration

  // From Speech Recognition (if speech detected)
  transcript: String?     // Raw transcription
  transcriptType: Enum    // .command | .lyrics | .ambiguous

  // From Sound Classification
  audioScene: Enum        // .music | .speech | .musicAndSpeech | .singing | .silence | .ambient

  // From Location
  latitude: Double
  longitude: Double
  placeName: String       // "Oakland, CA"
  neighborhood: String?   // "Temescal"
  venue: String?          // Nearby venue if applicable

  // Metadata
  observationDuration: Double    // How long the observation ran
  resolutionTrigger: Enum        // .shazamMatch | .holdRelease | .silenceTimeout | .hardTimeout
  timestamp: Date
}
```

### Assembly Logic

The context package is handed to the intelligence layer (Claude) with different instructions depending on what's available:

**Shazam match + no speech:**
"The user heard [song] by [artist] at [location]. Build the triad: Subject = [artist], Place = [location], Time = [releaseYear]. Explore the cultural connections."

**Shazam match + speech command:**
"The user heard [song] by [artist] at [location] and asked: '[transcript]'. Interpret the question in context of this artist/song/location and respond."

**Speech command only (no music):**
"The user is at [location] and said: '[transcript]'. Interpret as a cultural exploration instruction and build the appropriate triad."

**Lyrics (no Shazam match):**
"The user vocalized these words at [location]: '[transcript]'. This appears to be song lyrics. Identify the most likely song, then build the triad."

**Location only (silence):**
"The user is at [location] at [current time]. No audio context. Find the most culturally significant entities connected to this place and era, and build the triad."

---

## The Quiet Location Problem

When someone observes in silence and there's nothing culturally remarkable about their GPS coordinates (suburban living room, office park, etc.), the system needs a strategy for making the triad interesting.

### Resolution Cascade for Weak Locations

1. **Exact location** — Is there something notable at these coordinates? (Unlikely for most observations, but handles the "standing in a famous venue" case.)
2. **Neighborhood/district** — Cultural associations with the local area.
3. **City** — The nearest city with a meaningful cultural graph. Most observations will resolve here.
4. **Region** — If no city is strong, broaden to region (e.g., "Pacific Northwest" or "the Bay Area").
5. **Time anchor** — If location is weak at all levels, lean harder on the time dimension: "Today in cultural history" or "This week in [year]" using the current date.
6. **User affinity** — If the user has exploration history, surface something connected to their demonstrated interests, loosely anchored to whatever location/time is available.

The cascade should find something interesting within 1–2 levels for most users. The goal is that **no observation ever returns nothing.** Even in the most boring location, the current date provides enough of a time anchor to surface something.

---

## Edge Cases and Failure Modes

### Audio Permission Denied

If the user hasn't granted microphone permission, the observe button still works but operates in location-only mode. The haptic pattern goes directly to the 0.5 Hz "silence" pulse, and resolves after a brief pause. No error message — the experience degrades gracefully. The app should prompt for microphone permission during onboarding, but function without it.

### Location Permission Denied

If location is unavailable, the Place dimension of the triad is left open. The intelligence layer must be able to build a triad from Subject + Time alone, with Place as "unspecified." This is a degraded but functional experience. The user can manually set a place via voice command ("explore Berlin").

### Shazam Available but Returns Low Confidence

Shazam may return a match with low confidence. The system should have a confidence threshold below which the match is treated as a "no match." Suggested threshold: accept matches above 0.7 confidence; below that, discard and fall back to other signals.

### Speech Recognition Returns Garbage

In noisy environments, the speech transcript may be unintelligible. The system should evaluate transcript quality before using it:
- If the transcript is very short (< 3 words) and doesn't parse as a recognizable command, discard it
- If confidence scores from the speech recognizer are low across the board, discard
- Never send garbage text to Claude — it wastes tokens and produces confused responses

### Multiple Songs in Sequence

If the user observes and the song changes mid-observation (e.g., a playlist advances), Shazam will typically match the song that played longest. This is acceptable behavior. The system doesn't need to handle song transitions within a single observation.

### Network Unavailable

Shazam requires network access for matching. If offline:
- Sound classification still works (on-device)
- Speech recognition still works (on-device)
- Location still works
- The system can capture and buffer audio, then match when connectivity returns
- Or resolve with whatever on-device signals are available

Offline handling is a v2 concern. For v1, assume network availability.

---

## Timing Summary

| Phase | Duration | What Happens |
|-------|----------|-------------|
| **Button press** | Instant | All systems activate simultaneously. Strong haptic. |
| **Classification** | ~1 second | Sound classifier produces initial scene type. Haptic adjusts. |
| **Active observation** | 1–10 seconds | Shazam, speech recognition, and classification run continuously. Haptic pulses communicate state. |
| **Resolution** | Instant | Triggered by match, release, silence, or timeout. Terminal haptic fires. |
| **Post-observation processing** | 1–3 seconds | Intelligence layer receives context package, builds triad. Brief loading state. |
| **Result display** | — | Triad is populated, content appears, user can begin exploring. |

**Total time from tap to content:** Typically 4–10 seconds (Shazam match) or 6–13 seconds (timeout + processing). The haptic feedback makes this wait feel active and communicative rather than dead.

---

## Configurable Parameters

These values should be tunable during development:

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| `holdThresholdMs` | 300 | 200–500 | Tap vs. hold gesture threshold |
| `hardTimeoutSeconds` | 10 | 5–15 | Maximum observation duration |
| `silenceTimeoutSeconds` | 5 | 3–8 | Auto-resolve after this much silence |
| `shazamConfidenceThreshold` | 0.7 | 0.5–0.9 | Minimum Shazam confidence to accept |
| `baselineHapticHz` | 1.0 | 0.5–2.0 | Resting pulse frequency |
| `musicDetectedHapticHz` | 2.0 | 1.5–3.0 | Pulse frequency when music detected |
| `silenceHapticHz` | 0.5 | 0.25–1.0 | Pulse frequency when nothing detected |
| `resolutionRampDuration` | 1.0 | 0.5–2.0 | Duration of the accelerating ramp before resolution |
| `speechConfidenceThreshold` | 0.4 | 0.2–0.7 | Minimum transcript quality to use |
| `earlyResolutionEnabled` | true | — | Whether to resolve early on Shazam match or silence |

---

## What This Spec Does NOT Cover

- **The observe animation** — Defined in `anaspace-observe-animation-spec.md`. The haptic system defined here should synchronize with the visual animation but they are specified independently.
- **Triad engine logic** — How the intelligence layer builds and navigates the triad from the context package is defined in `anaspace-core-concepts.md`.
- **Rendering** — How results are displayed on screen is defined in `anaspace-rendering-system.md`.
- **Onboarding and permissions flow** — Separate spec. This document assumes permissions have been granted.
- **Personalization** — How user affinities influence what surfaces is a layer on top of the assembly logic described here.

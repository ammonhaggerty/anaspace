# Anaspace

**A cultural exploration engine for iOS, built entirely with Claude Code.**

<!-- TODO: Replace with demo video -->
<!-- [![Demo Video](docs/assets/thumbnail.png)](https://youtube.com/watch?v=REPLACE_ME) -->

> Press a button. The app listens to your world — identifies the song, hears your voice, knows where you are — and maps the cultural web connecting it all. Music, place, and time become coordinates in a living knowledge graph.

---

## What is Anaspace?

Anaspace is a multimodal observation engine disguised as an iOS app. You tap a button, and it simultaneously:

- **Identifies music** playing around you (Shazam)
- **Transcribes your voice** (on-device speech recognition)
- **Classifies the audio scene** (music, speech, silence, ambient)
- **Captures your location** (GPS + reverse geocoding)
- **Feels the moment** (haptic feedback patterns that shift with what it hears)

These signals converge into a **culture map** — a radial graph exploring how artists, places, movements, and eras connect. Every discovery is anchored by three coordinates: **Subject**, **Place**, and **Time**. Change any one, and the map regenerates — Claude re-evaluates the cultural connections from the new perspective.

### The Interaction

**Tap** (< 500ms) — *"Listen to my world."* The system runs until it finds something: a Shazam match, a silence timeout, or a hard limit.

**Hold** (>= 500ms) — *"Listen to me."* Walkie-talkie mode. Speak a command, recite lyrics, ask a question. Release when done.

Both modes start all services immediately. No delay, no routing — everything runs in parallel from the first millisecond.

### What Happens Next

After observation, the collected signals (song, transcript, scene, location, time) are routed to Claude, which builds a knowledge graph of cultural connections: collaborators, influences, followers, peers, creations, places, events, and movements. The result renders as a **radial graph** — the subject at the center, connections arranged by relevance and type in concentric rings.

From there, you can:

- **Tap the subject** to read its bio and history
- **Tap any connection** to explore its own cultural context, with a dedicated playlist
- **Change the year** to see how connections shift across eras
- **Change the location** to re-evaluate cultural relevance from a different geography
- **Browse history** to revisit and restore past explorations
- **Start fresh** from the history page to return to the observe screen

---

## Built with Claude Code

This project was built for the **Opus 4.6 Claude Code Hackathon**. The entire codebase — every Swift file, every animation, every service — was authored through Claude Code with Claude Opus 4.6.

### How I Built It

The development followed a structured workflow:

1. **Brainstorming** — Collaborative design sessions to define the concept, architecture, and interaction model. Five design specs were written before any code.

2. **Planning** — Detailed implementation plans broken into independent tasks with exact file paths, complete code, and build verification steps.

3. **Subagent-Driven Development** — Each task was dispatched to a fresh subagent with full context. After implementation, two review stages ran: spec compliance, then code quality. Issues were fixed before moving on.

4. **Parallel Execution** — Independent tasks (ShazamService, SoundAnalysisService, SpeechService) were implemented by three subagents simultaneously, each committing independently.

### The Numbers

| Metric | Value |
|--------|-------|
| Swift files | 48 |
| Lines of code | 9,144 |
| Commits | 48 |
| Apple frameworks used | 11 |
| Design specs written | 5 |
| Services implemented | 12 |

### Design-First Approach

Before writing code, we wrote specs:

| Document | Purpose |
|----------|---------|
| `anaspace-core-concepts.md` | Philosophy, persistent triad, knowledge graph model |
| `anaspace-rendering-system.md` | Character grid, three-layer system, animation patterns |
| `anaspace-observe-interaction-spec.md` | Gesture mechanics, audio pipeline, haptic feedback |
| `anaspace-observe-logic-spec.md` | Decision routing, assembly paths, signal collection |
| `anaspace-service-layer-design.md` | Service architecture, permission flow, implementation order |

These specs live in `.claude/` and served as the contract between planning and implementation.

---

## Architecture

### The Character Grid

Anaspace doesn't use SwiftUI's layout system for its main interface. Instead, it renders through a **fixed monospaced character grid** — closer to a 1970s terminal than a modern app.

```
33 columns x ~32 rows
JetBrains Mono, 15.52pt
Three independent layers (structure, content, transition)
96 CATextLayers total
5 colors, no gradients, no opacity
```

**Why?** Pixel-perfect control. Every character position is deterministic. Transitions use cell-by-cell wipe animations across the grid. The observe animation simulates radial echolocation — concentric waves of glyphs emanating outward while audio-reactive waves pulse inward from the edges.

The grid renders via Core Animation (`CATextLayer`), not SwiftUI. Dirty region tracking ensures only changed rows re-render. At 60 FPS, frame budget usage is under 1ms for typical updates.

### Service Layer

A centralized `ServiceManager` coordinates twelve services:

```
ServiceManager (@Observable, @MainActor)
 |
 |-- PermissionManager      Mic, location, speech, notifications, Apple Music
 |-- HapticService           CoreHaptics patterns (idle, music, speech, silence, success)
 |-- LocationService         GPS fix + reverse geocoding
 |-- AudioService            Shared AVAudioEngine, buffer fan-out
 |     |-- SoundAnalysisService   SNAudioStreamAnalyzer (scene classification)
 |     '-- SpeechService          SFSpeechRecognizer (on-device transcription)
 |-- ShazamService           SHManagedSession (manages own microphone)
 |-- MusicService            MusicKit catalog enrichment
 |-- ClaudeService           Culture map generation (Anthropic API)
 |-- AudioPlayerService      AVAudioEngine playback, VU metering, queue management
 |-- MusicQueueBuilder       Builds contextual playlists from culture connections
 '-- ObservationProgress     Phased lifecycle tracking (idle → capturing → processing → resolved)
```

**Key design decisions:**

- **All audio consumers run in parallel.** No classification step before routing. Shazam, speech, and sound analysis all receive audio from the first frame.
- **ShazamService manages its own mic.** `SHManagedSession` (iOS 17+) handles audio capture internally. Only SoundAnalysis and Speech consume from the shared AudioService.
- **Haptics are scene-reactive.** The haptic pattern shifts continuously based on what SoundAnalysis classifies — music pulse, speech texture, silence slow-throb.
- **500ms gesture boundary, zero-delay activation.** Services start on press. The tap/hold distinction is resolved later without any startup cost.
- **Audio session handoff.** Playback and capture never overlap — the player stops its engine and deactivates the audio session before capture begins, then rebuilds when new results arrive.

### Observation Flow

```
User presses Observe
        |
        v
 [Wipe transition → capture screen]
 [Haptics: idle pulse]
        |
        v
 [Parallel activation]
  Location ---+
  AudioEngine-+---> SoundAnalysis
              +---> Speech
  Shazam ---------> (own mic)
        |
        v
 [Monitor loop: 250ms poll]
  - Shazam match? --> resolve
  - Hard timeout?  --> resolve (tap only)
  - Silence 5s?   --> resolve (tap only)
  - Hold release?  --> resolve (hold only)
        |
        v
 [Collect signals]
  ShazamResult + Transcript + AudioScene + Location + Timestamp
        |
        v
 [Claude API → Culture Map]
  Subject + Connections + Bio + Birth info
        |
        v
 [Radial graph + Audio player queue]
```

### The Audio Player

Apple Music 30-second previews play automatically when results arrive. No subscription required — `MusicCatalogSearchRequest` searches freely, and `Song.previewAssets` provides DRM-free URLs.

The player runs on its own `AVAudioEngine` with real-time RMS metering from a tap on the main mixer node. A scrolling ticker displays the current track, and playback state persists across page navigation. Queue priority follows the cultural graph: subject artist first, then influences, followers, collaborators, and peers.

When navigating to an entity's detail page, the playlist switches to that entity's catalog. Going back restores the general playlist position.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 (strict concurrency) |
| UI | SwiftUI + Core Animation (`CATextLayer`) |
| Audio | AVAudioEngine, ShazamKit, SFSpeechRecognizer, SoundAnalysis |
| Maps | Mapbox GL |
| Haptics | CoreHaptics (`CHHapticEngine`) |
| Music | MusicKit, AVAudioEngine (playback) |
| Location | CoreLocation |
| AI | Claude API (Anthropic) |
| State | `@Observable` (Swift 6 Observation framework) |
| Async | `async/await`, `TaskGroup`, `AsyncStream`, structured concurrency |
| Min target | iOS 17.0 |

---

## Project Structure

```
anaspace/
  App/              Entry point, ContentView
  Grid/             Character grid renderer (CATextLayer-based)
  Animations/       Cascade, observe wave, wipe transition systems
  Components/       Map display, year digits, grid buttons, glyph masks
  Layout/           Formal sections, radial graph renderer
  Navigation/       Bottom nav bar, page routing, navigation manager
  Pages/            Home, info, history, options, onboarding
  Services/
    ServiceManager  Central coordinator
    ServiceTypes    Shared data models and configuration
    ObservationProgress  Phased lifecycle tracking
    HistoryStore    Persistent engagement history (12-entry ring buffer)
    Permissions/    System permission tracking
    Location/       GPS + reverse geocoding
    Audio/          AudioService hub, Shazam, SoundAnalysis, Speech
    Haptics/        CoreHaptics patterns
    Music/          MusicKit catalog, AudioPlayerService, MusicQueueBuilder
    AI/             Claude API integration
  Storage/          AppState, LocalStore (UserDefaults persistence)
```

---

## Setup

### Prerequisites

- Xcode 16+ (Swift 6.0)
- iOS 17.0+ device or simulator
- Mapbox account (for map display)

### Configuration

1. Clone the repository
2. Copy the secrets template:
   ```bash
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```
3. Add your API keys to `Secrets.xcconfig`:
   ```
   MAPBOX_TOKEN = your_mapbox_token_here
   CLAUDE_API_KEY = your_claude_api_key_here
   ```
4. Open `anaspace.xcodeproj` in Xcode
5. Build and run

`Secrets.xcconfig` is gitignored. Never commit API keys.

---

## Build Progression

The project was built incrementally across 48 commits:

**Foundation** — Character grid prototype, cascade animation, observe wave system with dual-wave interference.

**Components** — Navigation bar with SVG icons, grid-aligned buttons, Mapbox map widget masked through character glyphs, year display with custom digit assets.

**Interactive features** — Full-screen map picker with location labels, year picker with drag scrolling and momentum physics.

**Service layer** — 13-task systematic buildout: data models, permissions, haptics, location, shared audio engine, Shazam, sound analysis, speech recognition, MusicKit, Claude stub, central coordinator, UI wiring with gesture detection.

**Onboarding** — Sequential permission pre-read screens explaining each service before requesting access.

**Claude integration** — Phased observation lifecycle, Anthropic API integration for culture map generation, entity system with eight connection types, triad-anchored prompting (subject + place + time).

**Exploration** — Subject and entity info pages with wipe transitions, location/year/subject change queries that regenerate the graph from new perspectives, contextual evaluation status display.

**History** — Persistent 12-entry engagement history with instant restore, reset-to-observe button for starting fresh.

**Audio player** — Apple Music preview playback via AVAudioEngine, real-time VU metering, scrolling ticker, contextual playlists that follow graph exploration, entity-specific playlists when viewing connections.

**Polish** — Idea shortcut cards on the observe screen, radial graph layout refinement with bracket framing, transition bleed-through fix, observe button pulse animation, autoplay settings with session-aware pause persistence, options page with entity key legend and GitHub link.

---

## Current State

**Working:**
- Complete character-grid rendering with three-layer compositing
- Observe animation with radial echolocation simulation
- Full audio pipeline (Shazam + Speech + SoundAnalysis running in parallel)
- Claude API integration generating culture maps from observation signals
- Radial knowledge graph with eight entity types and relevance-based placement
- Subject and entity detail pages with biographical info
- Triad re-evaluation: change location, year, or subject and the graph regenerates
- Apple Music preview playback with contextual playlists and VU metering
- Haptic feedback reactive to audio scene classification
- Interactive map selection with reverse geocoding
- Year picker with momentum scrolling
- Persistent history with 12-entry store and instant restore
- Options page with autoplay toggle and entity type legend
- Onboarding flow with sequential permission screens
- Wipe transitions between all pages
- Tap vs. hold gesture detection at 500ms threshold

**Ideas for the future:**
- Full-length playback via Apple Music subscription integration
- Social sharing of culture maps
- Offline caching of explored graphs
- Deeper Claude conversations about connections
- AR overlay mode

---

## License

Mozilla Public License Version 2.0

---

<sub>Built with Claude Opus 4.6 via Claude Code.</sub>

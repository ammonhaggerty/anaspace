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

These signals converge into a **culture map** — an exploration of how artists, places, and eras connect. Every discovery is anchored by three coordinates: **Subject**, **Place**, and **Time**. Change any one, and the others adapt intelligently.

### The Interaction

**Tap** (< 500ms) — *"Listen to my world."* The system runs until it finds something: a Shazam match, a silence timeout, or a hard limit.

**Hold** (>= 500ms) — *"Listen to me."* Walkie-talkie mode. Speak a command, recite lyrics, ask a question. Release when done.

Both modes start all services immediately. No delay, no routing — everything runs in parallel from the first millisecond.

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
| Swift files | 41 |
| Lines of code | 4,527 |
| Commits | 33 |
| Apple frameworks used | 10 |
| Design specs written | 5 |
| Services implemented | 9 |

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

**Why?** Pixel-perfect control. Every character position is deterministic. Transitions use Perlin noise fields flowing through the grid. The observe animation simulates radial echolocation — concentric waves of glyphs emanating outward while audio-reactive waves pulse inward from the edges.

The grid renders via Core Animation (`CATextLayer`), not SwiftUI. Dirty region tracking ensures only changed rows re-render. At 60 FPS, frame budget usage is under 1ms for typical updates.

### Service Layer

A centralized `ServiceManager` coordinates nine services:

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
 '-- ClaudeService           Culture map generation (stubbed)
```

**Key design decisions:**

- **All audio consumers run in parallel.** No classification step before routing. Shazam, speech, and sound analysis all receive audio from the first frame.
- **ShazamService manages its own mic.** `SHManagedSession` (iOS 17+) handles audio capture internally. Only SoundAnalysis and Speech consume from the shared AudioService.
- **Haptics are scene-reactive.** The haptic pattern shifts continuously based on what SoundAnalysis classifies — music pulse, speech texture, silence slow-throb.
- **500ms gesture boundary, zero-delay activation.** Services start on press. The tap/hold distinction is resolved later without any startup cost.

### Observation Flow

```
User presses Observe
        |
        v
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
 [Decision Router --> Claude] (next phase)
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 (strict concurrency) |
| UI | SwiftUI + Core Animation (`CATextLayer`) |
| Audio | AVAudioEngine, ShazamKit, SFSpeechRecognizer, SoundAnalysis |
| Maps | Mapbox GL |
| Haptics | CoreHaptics (`CHHapticEngine`) |
| Music | MusicKit |
| Location | CoreLocation |
| AI | Claude API (stubbed, next phase) |
| State | `@Observable` (Swift 6 Observation framework) |
| Async | `async/await`, `TaskGroup`, structured concurrency |
| Min target | iOS 17.0 |

---

## Project Structure

```
anaspace/
  App/              Entry point, ContentView
  Grid/             Character grid renderer (CATextLayer-based)
  Animations/       Cascade, observe wave, transition systems
  Components/       Map display, year digits, grid buttons, glyph masks
  Layout/           Formal sections, radial graph renderer
  Navigation/       Bottom nav bar, page routing
  Pages/            Home, map selection, year picker, history, options
  Services/
    ServiceManager  Central coordinator
    ServiceTypes    Shared data models and configuration
    Permissions/    System permission tracking
    Location/       GPS + reverse geocoding
    Audio/          AudioService hub, Shazam, SoundAnalysis, Speech
    Haptics/        CoreHaptics patterns
    Music/          MusicKit catalog
    AI/             Claude integration (stubbed)
  Storage/          AppState, LocalStore
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

The project was built incrementally across 33 commits:

**Foundation** — Character grid prototype, cascade animation, observe wave system with dual-wave interference.

**Components** — Navigation bar with SVG icons, grid-aligned buttons, Mapbox map widget masked through character glyphs, year display with custom digit assets.

**Interactive features** — Full-screen map picker with location labels, year picker with drag scrolling and momentum physics.

**Service layer** — 13-task systematic buildout: data models, permissions, haptics, location, shared audio engine, Shazam, sound analysis, speech recognition, MusicKit, Claude stub, central coordinator, UI wiring with gesture detection.

---

## Current State

**Working:**
- Complete character-grid rendering with three-layer compositing
- Observe animation with radial echolocation simulation
- Full audio pipeline (Shazam + Speech + SoundAnalysis running in parallel)
- Haptic feedback reactive to audio scene classification
- Interactive map selection with reverse geocoding
- Year picker with momentum scrolling
- Tap vs. hold gesture detection at 500ms threshold
- Permission management for all system services

**Next phase:**
- Wire ClaudeService to Anthropic API for culture map generation
- Implement decision router (signal collection to assembly paths)
- Build onboarding flow with permission request screens
- Populate history and options pages
- Add exploration persistence

---

## License

Mozilla Public License Version 2.0

---

<sub>Built with Claude Opus 4.6 via Claude Code.</sub>

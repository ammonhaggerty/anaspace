# Anaspace

**A cultural exploration engine for iOS, built from scratch in ~18 hours using Claude Code Opus 4.6. Part of the February 2026 hackathon for Claude Code's 1st birthday.**

https://github.com/user-attachments/assets/6a8ffbe9-c2a1-448b-9131-2b0104d62dde

---

Anaspace is a cultural exploration app for iOS. You hear a song, tap observe, and the app uses Shazam to identify the music while capturing your location and anchoring you in time. From that moment, it builds a triad — subject, place, and time — and maps the web of cultural connections between them. You can pivot on any dimension to explore how artists, cities, genres, and eras are linked, with curated music samples anchoring each node so the journey is something you hear, not just read. The entire interface is built on a character-cell matrix rendered in JetBrains Mono — the typeface grid serves as both the display system and the animation engine, with waves of glyphs pulsing across the screen as the app listens and thinks.

The app exists because algorithms have made music infinite and culture disposable. Streaming platforms optimize for engagement, not meaning, and the web of influence that gives art its depth has been flattened into a recommendation feed. Anaspace restores that context — not by replacing how you find music, but by revealing the connections that make what you're already hearing worth paying attention to.

Anaspace is fully data sovereign: no sign-in, no data collection, no servers. The intent is to run entirely on device-side models, eliminating AI costs and ensuring the tool doesn't participate in the economic structures that shortchange artists. I wasn't able to finish local model integration for this hackathon, but I'm close — the plan is to release Anaspace as a free app with zero model cost. There is extraordinary music, art, and culture being forgotten every day, and this is a tool for finding it right where you are.

**Note:** Running Anaspace on the Apple Foundation Model did not perform well enough, so for now I'm using Claude Haiku 4.6 and it will remain an open-source experiment. When Apple improves their internal model I will release this on the App Store as a free app. 

---

## How It Works

### Observe

The observe button is the only way in. There is no search bar, no browse interface, no text input. You either listen to the world or speak to the app.

**Tap** — *"Listen to my world."* The app opens its ears to the environment. Shazam identifies music, speech recognition captures voice, sound classification reads the scene, and location services anchor you in space. Everything runs in parallel from the first millisecond — no routing, no classification step before activation.

**Hold** — *"Listen to me."* Walkie-talkie mode. Speak a command ("show me the jazz scene here in the 1960s"), recite lyrics, ask a question. Release when done.

Both gestures produce a context package — song, transcript, audio scene, location, timestamp — that gets assembled into a culture map.

### The Triad

Every view in Anaspace is anchored by three co-equal dimensions: **Subject** (an artist, genre, or movement), **Place** (a city, venue, or region), and **Time** (a year, decade, or era). All three are always present. The content shown is the intersection of all three.

The power is in pivoting. Change the year from 1971 to 1930, and the system asks: who carried Sly Stone's creative energy in that era? Change the place from Oakland to Berlin, and it asks: who is the Sly Stone of Berlin? Change the subject to Kraftwerk, and the map reorients — Oakland probably falls away, Düsseldorf rises, and the time anchor shifts to their peak. The system finds cultural analogs by scoring candidates on genre overlap, era relevance, place connection, and influence lineage. The analog isn't just someone famous from that place and time — it's the person who occupies the most similar cultural role.

### The Culture Map

After observation, the collected signals route to the intelligence layer, which builds a knowledge graph of cultural connections: collaborators, influences, followers, peers, creations, places, events, and movements. The result renders as a radial graph — the subject at the center, connections arranged by relevance and type in concentric rings. Each node has a curated playlist. Tapping a connection explores its own cultural context from a new center.

---

## The Rendering Engine

Anaspace doesn't use SwiftUI's layout system for its main interface. The entire experience renders through a character-cell matrix — a fixed grid of monospaced glyphs composited via Core Animation, closer to a 1970s terminal display than a modern app. The grid is the display system, the animation engine, and the aesthetic identity of the project.

### Why JetBrains Mono

The font choice is foundational, not decorative. JetBrains Mono provides 1,736 glyphs across two weights (regular and bold), including an unusually rich set of box-drawing characters, block elements, geometric shapes, and mathematical symbols. The full-height block characters (`█ ▇ ▆ ▅`) and fractional-width blocks (`▉ ▊ ▋ ▌ ▍ ▎`) enable smooth density gradients within the grid. The box-drawing set (`╬ ╠ ╣ ╦ ╩ ┃`) provides structural scaffolding. Decorative and mathematical glyphs (`◊ ◆ ⊕ ⊗ ◉ ✦`) serve as interference textures during wave collisions.

At 15.52pt with 11% letter spacing and 22.3pt line height, the font produces roughly equal horizontal and vertical cell spacing — making each cell nearly square. This is unusual for monospaced type and critical for the animation system: radial waves propagate with equal speed in all directions rather than stretching along one axis. The two font weights provide an additional visual dimension without adding a color — bold reinforces layer identity and distinguishes entity types within the same palette.

### Grid Dimensions

```
33 columns (fixed across all devices)
~32 rows (calculated dynamically from available vertical space)
15.52pt JetBrains Mono, 11% letter spacing, 22.3pt line height
Base device: iPhone 17 Pro (402 × 874pt)
Top padding: 63px (camera/Dynamic Island clearance)
Side margins: 20px each
Bottom footer: 97px (navigation, outside the grid)
```

The column count is fixed at 33. Row count adapts to device height by dividing available vertical space by line height. Most modern iPhones land at 31–33 rows. Each row is an independent rendering unit — no text wrapping between rows, no cascading relayout. Changing one row never affects another.

### The Three-Layer System

Three layers stack visually, all perfectly aligned to the same 33×N grid. Each layer is fully independent — no layer influences another's content or visibility.

```
╔══════════════════════════════════════════════╗
║                                              ║
║   7. Bottom Navigation (97px footer zone)    ║
║  ┌────────────────────────────────────────┐  ║
║  │  6. Transition Layer (top)             │  ║
║  │     Temporary animation during observe │  ║
║  │     and page transitions. Empty when   │  ║
║  │     inactive — passes through.         │  ║
║  ├────────────────────────────────────────┤  ║
║  │  5. Content Layer (middle)             │  ║
║  │     Entity names, labels, triad bar,   │  ║
║  │     descriptions. Dark colors.         │  ║
║  │     Relatively sparse — structure      │  ║
║  │     peeks through gaps.                │  ║
║  ├────────────────────────────────────────┤  ║
║  │  4. Structure Layer (bottom)           │  ║
║  │     Visual form and texture. Light     │  ║
║  │     colors. Mostly static, subtle      │  ║
║  │     breathing during idle.             │  ║
║  ├────────────────────────────────────────┤  ║
║  │  3. Overlay Buttons (grid-aligned)     │  ║
║  │  2. Year Indicator (own font)          │  ║
║  │  1. Map System                         │  ║
║  ├────────────────────────────────────────┤  ║
║  │  0. Background Color (#CBB4A5)         │  ║
║  └────────────────────────────────────────┘  ║
║                                              ║
╚══════════════════════════════════════════════╝
```

The compositing rule is pure precedence: for any cell, the topmost layer with a non-empty glyph wins. No blending, no opacity, no transparency — a cell is either occupied by a glyph in one of five colors, or it's empty and the layer below shows through. This binary simplicity means a full screen state across all three layers is approximately 3KB of raw data, trivially snapshotted and diffed.

### Color System

Exactly five colors in the entire project:

| Color | Hex | Role |
|-------|-----|------|
| Warm tan | `#CBB4A5` | Background |
| Dark brown | `#301818` | Primary content, outbound wave cores |
| Light warm | `#E4D7CE` | Structure, wave leading/trailing edges |
| White | `#FFFFFF` | Inbound audio-reactive waves |
| Red | `#FF0000` | Sparse accent — occasional sparks in wave cores |

No gradients. No additional colors. The two font weights (regular and bold) provide visual variation without expanding the palette.

### Rendering Implementation

Each row on each layer is a single `CATextLayer` — 32 rows × 3 layers = 96 instances total. Core Animation composites these at 60 FPS on the GPU automatically. Each row update changes the `string` property as an `NSAttributedString` with per-character color attributes. Unchanged layers are cached as GPU textures with zero re-render cost. Dirty region tracking ensures only changed rows update. During peak animation (full-screen observe transition), the realistic per-frame cost is 6–10 `CATextLayer` string mutations, each well under 1ms — substantial headroom within the 16.6ms frame budget.

### Animation System

Three animation patterns form a clear energy hierarchy — idle (near-zero) → page transitions (medium) → observe (peak) — all sharing the same density-based glyph language at different intensities.

**Observe (hero animation).** Concentric waves of glyphs radiate outward from the button position at bottom center. Dark semicircular arcs expand upward with light leading edges, dense cores, and sparse trailing edges. Simultaneously, audio-reactive waves in white pulse inward from the grid edges, their density driven by real-time RMS amplitude. Where outbound and inbound waves collide, interference cells flash with geometric glyphs at high chaos — the visual texture of two signals meeting.

**Page transitions.** Perlin noise fields map to glyph density, creating organic cloud shapes that roll across the screen. Clouds cover current content, the structure and content layers swap underneath, clouds roll away to reveal the new state. 300–400ms total.

**Idle state.** Background structure layer breathes — small regions swap between glyphs of similar density as a noise field drifts through. Movement is perceptible in peripheral vision but hard to track in direct focus. Like watching water.

### Density Tiers

Glyphs are categorized by visual weight into five tiers. The same tier system drives all three animation patterns:

```
Tier 1 (minimal):  · ˙ ' ` , .        — barely visible
Tier 2 (light):    - ~ ° ˜ ¯          — sparse marks
Tier 3 (medium):   + * # × ÷ ≡ ╬ ┼   — moderate coverage
Tier 4 (heavy):    ░ ▒ ╬ ╠ ╣ ╦ ╩ ■ ▌  — near-solid fills
Tier 5 (solid):    █ ▇ ▆ ▉ ▊ ▋        — full blocks
```

Randomizing within a density tier creates living texture that reads as consistent visual weight with organic variation. The observe animation controls which tiers are active based on wave position and audio amplitude; the idle state uses only tiers 1–2 at glacial speed.

---

## Architecture

### Service Layer

A centralized `ServiceManager` coordinates twelve services, all running under Swift 6 strict concurrency:

```
ServiceManager (@Observable, @MainActor)
 │
 ├── PermissionManager        Mic, location, speech, Apple Music
 ├── HapticService             CoreHaptics patterns (idle, music, speech, silence, success)
 ├── LocationService           GPS + reverse geocoding
 ├── AudioService              Shared AVAudioEngine, buffer fan-out
 │     ├── SoundAnalysisService     Scene classification (music, speech, silence, ambient)
 │     └── SpeechService            On-device transcription
 ├── ShazamService             SHManagedSession (manages own mic)
 ├── MusicService              MusicKit catalog enrichment
 ├── ClaudeService             Culture map generation (Anthropic API)
 ├── AudioPlayerService        AVAudioEngine playback, VU metering, queue management
 ├── MusicQueueBuilder         Contextual playlists from culture connections
 └── ObservationProgress       Phased lifecycle (idle → capturing → processing → resolved)
```

All audio consumers run in parallel from the first frame. ShazamKit manages its own microphone via `SHManagedSession`. Haptic feedback shifts continuously based on what SoundAnalysis classifies — a music pulse, a speech texture, a silence slow-throb. The 500ms gesture boundary costs zero startup time because services are already running when the distinction resolves.

### Audio Player

Apple Music 30-second previews play automatically when results arrive — no subscription required. The player runs on its own `AVAudioEngine` with real-time RMS metering. Queue priority follows the cultural graph: subject artist first, then influences, followers, collaborators, and peers. Navigating to a connection switches the playlist to that entity's catalog; going back restores position.

### Haptic Language

Haptics serve as a non-visual communication channel. The user can keep their phone in a pocket and know from feel alone what the app is detecting: a steady 1 Hz pulse for baseline listening, doubled to 2 Hz when music is detected, slowed to 0.5 Hz in silence, a distinct da-dum rhythm for speech, an accelerating ramp toward resolution, and a crisp triplet for success.

---

## The Path to Data Sovereignty

The current build uses Claude's API for cultural knowledge synthesis. This works well but creates two problems: it costs money per query, and it sends observation data to a server. Both violate the project's core principles. The goal is to replace the cloud API with on-device language models — making Anaspace fully sovereign, fully free, and fully offline-capable.

### The On-Device Moment

Both Apple and Google are shipping capable on-device language models to developers right now, and the trajectory is unmistakable.

**Apple Foundation Models** (iOS 26+) provides access to an on-device LLM with characteristics remarkably similar to where OpenAI's GPT-3.5 was at launch: capable of structured reasoning, responsive enough for production use (~1-2 seconds per query), and running entirely on the device's neural engine. The framework supports structured generation via `@Generable` types, streaming responses for progressive UI updates, and session prewarming for near-instant first queries.

**Google Gemini Nano** offers a parallel path on Android. Through the ML Kit GenAI APIs and the AICore system service, Android developers get access to on-device inference with the same core value proposition: no network dependency, no cloud compute costs, complete data privacy. Google's approach includes feature-specific LoRA fine-tuning for out-of-the-box quality across use cases like summarization, rewriting, and free-form prompting via the new Prompt API. The recently announced Gemma 3n architecture — engineered in collaboration with Qualcomm, MediaTek, and Samsung — signals that on-device AI is a first-class platform priority, not an experiment.

This isn't a coincidence. More than a decade ago, I worked alongside [Blaise Agüera y Arcas](https://research.google/people/106776/) at Microsoft, where we were exploring on-device machine learning before the tools existed to make it practical. Blaise went on to lead on-device ML for Android and Pixel at Google, invented Federated Learning, and is now a VP and Fellow serving as Google's CTO of Technology & Society. He's been thinking about privacy-preserving, device-local intelligence longer than almost anyone in the industry. The fact that both major mobile platforms are now shipping these capabilities to developers tells me the window for apps like Anaspace — apps that deliver sophisticated AI experiences with zero data extraction — is wide open.

**Anaspace will ship on both platforms.** iOS via Apple Foundation Models, Android via Gemini Nano's Prompt API. Same architecture, same principles, same zero-cost model.

### The Core Challenge: 4K Context

The on-device models have constrained context windows — Apple's is 4,096 tokens including system instructions, prompt, and output combined. Anaspace's culture map queries are inherently rich: an artist's bio, their influences, genre history, geographic connections, temporal context. Fitting this into 4K tokens while preserving the quality of cultural insight is the central technical challenge.

### The Strategy: Decomposed Micro-Queries

The approach draws directly from techniques I validated in another Foundation Models project ([AppleFoundationMatchMaker](https://github.com/ammonshepherd/AppleFoundationMatchMaker)), where I solved similar context constraints:

**Fresh sessions per query.** `LanguageModelSession` accumulates context across turns, quickly exceeding the token limit. The solution is to create a dedicated session for each independent query — clean context, predictable token budget, no accumulation.

**Aggressive prompt compression.** Instead of sending rich narrative context, distill each query to structured facts: artist name, genre, origin city, active years, known influences — as compact key-value pairs. The model narrates from facts rather than reasoning from scratch. Target: ~700-800 tokens per prompt, leaving ~500-800 tokens for output and a comfortable buffer.

**Chained micro-queries instead of monolithic requests.** Rather than asking for a complete culture map in one call, decompose into focused queries that each fit comfortably in the context window: (1) narrate the connection between this artist and this place, (2) list 3 key influences as structured output, (3) describe this influence relationship in one sentence. Each query is small, grounded in provided facts, and the UI renders results progressively — which actually feels better than waiting for one large response.

**Structured generation for reliability.** Foundation Models' `@Generable` types with `@Guide` annotations produce typed, parseable output — no JSON parsing failures, no prompt engineering to prevent markdown. The model returns exactly the data structure the UI expects.

**The LLM narrates, it doesn't research.** This is the foundational principle. The on-device model doesn't need to know cultural history from its training data. It needs to take structured facts — pulled from MusicKit, Wikidata, Wikipedia extracts — and weave them into coherent, evocative micro-narratives. That's well within a small model's capability. The knowledge graph does the research; the LLM tells the story.

### What This Means for Users

When this integration is complete, Anaspace becomes a zero-cost, zero-compromise cultural exploration tool. No API keys, no server costs, no data leaving the device. The app works offline. There's no business model that depends on user data, no subscription that gates features, and no ongoing compute cost that pressures the developer to monetize attention. The intelligence runs on hardware the user already owns.

---

## Built with Claude Code

This project was built for the **Opus 4.6 Claude Code Hackathon**. Every Swift file, every animation, every service was authored through Claude Code with Claude Opus 4.6.

### Design-First Development

Before writing any code, five detailed specification documents were written collaboratively — defining the philosophy, interaction model, rendering system, audio pipeline, and service architecture. These specs served as the contract between planning and implementation:

| Document | Purpose |
|----------|---------|
| `anaspace-core-concepts.md` | Persistent triad, knowledge graph model, narrative layers, analog finding |
| `anaspace-rendering-system.md` | Character grid, three-layer compositing, animation patterns, color system |
| `anaspace-observe-interaction-spec.md` | Gesture mechanics, parallel audio pipeline, haptic feedback language |
| `anaspace-observe-logic-spec.md` | Decision routing, context assembly, signal collection |
| `anaspace-service-layer-design.md` | Service architecture, permission flow, implementation order |

### The Numbers

| Metric | Value |
|--------|-------|
| Swift files | 48 |
| Lines of code | 9,144 |
| Commits | 48 |
| Apple frameworks | 11 |
| Design specs | 5 |
| Services | 12 |
| Development time | ~18 hours |

### Development Workflow

Implementation followed a structured pipeline: detailed plans broken into independent tasks with exact file paths and build verification steps, dispatched to fresh subagents with full context. Independent services (Shazam, SoundAnalysis, Speech) were implemented by parallel subagents simultaneously, each committing independently. After implementation, two review stages ran — spec compliance, then code quality — with issues fixed before moving on.

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
| AI | Claude API (Anthropic) — transitioning to Apple Foundation Models + Gemini Nano |
| State | `@Observable` (Swift Observation framework) |
| Async | `async/await`, `TaskGroup`, `AsyncStream`, structured concurrency |
| Target | iOS 17.0+ |

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
    ServiceManager       Central coordinator
    ServiceTypes         Shared data models and configuration
    ObservationProgress  Phased lifecycle tracking
    HistoryStore         Persistent engagement history (12-entry ring buffer)
    Permissions/         System permission tracking
    Location/            GPS + reverse geocoding
    Audio/               AudioService hub, Shazam, SoundAnalysis, Speech
    Haptics/             CoreHaptics patterns
    Music/               MusicKit catalog, AudioPlayerService, MusicQueueBuilder
    AI/                  Claude API integration
  Storage/               AppState, LocalStore (UserDefaults persistence)
```

---

## Setup

### Prerequisites

- Xcode 16+ (Swift 6.0)
- iOS 17.0+ device (simulator works for UI, device required for Shazam/haptics)
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

## Personal Note: Building with Claude Opus 4.6

I haven't built an iOS app in more than a decade. Anaspace involved deeply technical problems — Core Animation rendering pipelines, parallel audio processing across four simultaneous services, real-time haptic feedback driven by sound classification, a custom character-grid animation engine with interference physics — and I was able to tackle all of them with remarkably little friction.

The collaboration with Claude Opus 4.6 through Claude Code felt effortless and focused. Nearly every goal we set out to accomplish was achieved with a high degree of success. I've been prototyping with AI coding assistance for a couple of years now, and I've grown comfortable getting the best results from these tools. For this project, I deliberately chose hard problems that push what coding AI is good at: real-time audio pipelines, GPU-composited animation systems, complex state coordination across a dozen concurrent services.

I took on this hackathon while delivering an ambitious project at work and supporting my family over a holiday weekend. The entire project was built start to finish in about 15 hours. I often had 2-3 instances of Claude Opus working simultaneously, with dozens of subagents running in parallel. Toward the end, I could feel the complexity of the codebase beginning to create interpretation errors — managing all the guidance and context reduced the velocity I could sustain between compacting. That's a real boundary, and an interesting one to have found.

All in all, I'm elated with what I can build on my own. While I continue to feel conflicted about AI's impact on society, the responsibility owed by technology companies, and the dangerous lack of regulatory guidance from political leadership, it is a magical time to be a builder and maker.

---

## License

Mozilla Public License Version 2.0

---

<sub>Built with Claude Opus 4.6 via Claude Code.</sub>

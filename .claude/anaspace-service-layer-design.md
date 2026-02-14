# Anaspace — Service Layer Design

**Date:** 2026-02-14
**Scope:** Foundation + Apple services (Claude stubbed)

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Claude API auth | Secrets.xcconfig | Same pattern as Mapbox token. Direct API calls from device. |
| Service architecture | Centralized ServiceManager | One @Observable object owns all services, coordinates activation. ContentView talks to one object. |
| Permission timing | Onboarding flow | Dedicated permission screens during first launch, requested in sequence. |
| Apple Music auth | Optional sign-in with degraded path | Prompt during onboarding, allow skip. Signed-in: richer metadata + playback links. Skipped: Shazam results + basic catalog lookups. |

---

## Architecture

### Service Hierarchy

```
ServiceManager (@Observable, @MainActor)
├── permissionManager: PermissionManager
├── locationService: LocationService
├── audioService: AudioService            // owns AVAudioEngine, shared audio buffer
│   ├── shazamService: ShazamService      // fed by audioService
│   ├── soundAnalysisService: SoundAnalysisService  // fed by audioService
│   └── speechService: SpeechService      // fed by audioService
├── hapticService: HapticService
├── musicService: MusicService            // MusicKit catalog + optional auth
└── claudeService: ClaudeService          // stubbed for now
```

### Service Protocol

Every observation service conforms to:

```swift
protocol ObservationService {
    var isAvailable: Bool { get }
    func activate() async throws
    func deactivate()
}
```

### File Structure

```
anaspace/
├── Services/
│   ├── ServiceManager.swift              // Central coordinator
│   ├── Permissions/
│   │   └── PermissionManager.swift       // System permission requests + status tracking
│   ├── Audio/
│   │   ├── AudioService.swift            // AVAudioEngine, shared buffer management
│   │   ├── ShazamService.swift           // ShazamKit song identification
│   │   ├── SoundAnalysisService.swift    // Apple Sound Analysis scene classification
│   │   └── SpeechService.swift           // SFSpeechRecognizer on-device transcription
│   ├── Location/
│   │   └── LocationService.swift         // CoreLocation GPS + reverse geocoding
│   ├── Haptics/
│   │   └── HapticService.swift           // CoreHaptics patterns for observation feedback
│   ├── Music/
│   │   └── MusicService.swift            // MusicKit catalog queries + optional auth
│   └── AI/
│       └── ClaudeService.swift           // Stubbed — Anthropic API client
├── Models/
│   ├── ObservationSignals.swift          // Collected signals from one observation
│   ├── AudioScene.swift                  // Sound classification enum
│   └── ServiceConfiguration.swift        // Configurable parameters from spec
```

### Observation Flow

```
User taps/holds Observe button
        │
        ▼
ServiceManager.beginObservation(mode: .tap | .hold)
        │
        ├── Creates ObservationSession (collects signals)
        ├── hapticService.startPulse()
        │
        ├── Parallel activation (TaskGroup):
        │   ├── locationService.activate()     → session.location
        │   ├── audioService.activate()        → starts AVAudioEngine
        │   │   ├── shazamService.activate()   → session.shazamResult
        │   │   ├── soundAnalysisService.activate() → session.audioScene
        │   │   └── speechService.activate()   → session.transcript
        │   └── (haptics driven by soundAnalysis callbacks)
        │
        ├── Resolution (depends on mode):
        │   ├── Tap: Shazam match / silence timeout / hard timeout
        │   └── Hold: button release
        │
        ▼
ServiceManager.resolveObservation() → ObservationSignals
        │
        ├── All services deactivated
        ├── Terminal haptic
        └── Signals handed to DecisionRouter (future)
```

### Permission Manager

Wraps all system permission APIs into one place:

```swift
@Observable @MainActor
final class PermissionManager {
    var microphone: PermissionState = .undetermined
    var location: PermissionState = .undetermined
    var speechRecognition: PermissionState = .undetermined
    var notifications: PermissionState = .undetermined
    var appleMusic: PermissionState = .undetermined

    func requestMicrophone() async -> PermissionState
    func requestLocation() async -> PermissionState
    func requestSpeechRecognition() async -> PermissionState
    func requestNotifications() async -> PermissionState
    func requestAppleMusic() async -> PermissionState

    func refreshAll() async  // Syncs with system state on app launch
}
```

Replaces the current `PermissionStatus` struct in `AppState`. AppState will hold a reference to the PermissionManager (or ServiceManager which contains it).

### Onboarding Permission Sequence

1. **Microphone** — "Anaspace listens to the world around you" (required for core function)
2. **Location** — "Your location anchors every observation" (required for core function)
3. **Speech Recognition** — "Speak to guide your exploration" (required, on-device)
4. **Apple Music** — "Sign in for richer music context" (optional, skip allowed)
5. **Notifications** — "Get notified about cultural moments nearby" (optional, skip allowed)

If mic or location is denied, the app still launches but Observe is disabled with an explanation.

### Info.plist Additions Required

```xml
NSMicrophoneUsageDescription — "Anaspace listens to identify music and hear your voice"
NSLocationWhenInUseUsageDescription — "Your location anchors every cultural observation"
NSSpeechRecognitionUsageDescription — "Voice commands guide your cultural exploration"
NSAppleMusicUsageDescription — "Access Apple Music for richer song and artist context"  (MusicKit)
NSUserNotificationsUsageDescription — handled via UNUserNotificationCenter
```

### Entitlements File Required

```
com.apple.developer.applesignin — Default (for future Apple Sign-In)
com.apple.developer.musickit — (if using MusicKit subscription features)
```

### Secrets.xcconfig Additions

```
MAPBOX_TOKEN = <existing>
CLAUDE_API_KEY = <to be added>
```

### Data Models

```swift
/// Collected signals from one observation
struct ObservationSignals {
    var shazamResult: ShazamResult?       // song, artist, album, confidence
    var transcript: TranscriptResult?      // text, confidence, word count
    var audioScene: AudioScene?            // .music, .speech, .silence, etc.
    var location: LocationResult?          // coordinates, placemark, place name
    var timestamp: Date
    var mode: ObservationMode              // .tap or .hold
    var duration: TimeInterval
}

enum ObservationMode {
    case tap    // system-controlled duration
    case hold   // user-controlled duration
}

enum AudioScene: String, Codable {
    case music, speech, musicAndSpeech, singing, silence, ambient
}

/// Configurable parameters (from spec)
struct ServiceConfiguration {
    var holdThresholdMs: Int = 500
    var hardTimeoutSeconds: Double = 10
    var silenceTimeoutSeconds: Double = 5
    var shazamConfidenceThreshold: Double = 0.7
    var speechConfidenceThreshold: Double = 0.4
    var commandMaxWords: Int = 20
    var discardShortTranscripts: Int = 3
}
```

### Audio Service Detail

AudioService is the most complex because it owns the shared AVAudioEngine and feeds three consumers:

```swift
@Observable @MainActor
final class AudioService: ObservationService {
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // Consumers attached to the audio tap
    let shazamService: ShazamService
    let soundAnalysisService: SoundAnalysisService
    let speechService: SpeechService

    func activate() async throws {
        // 1. Configure AVAudioSession for recording
        // 2. Create AVAudioEngine
        // 3. Install tap on inputNode
        // 4. Route audio buffer to all three consumers
        // 5. Start engine
    }

    func deactivate() {
        // Remove tap, stop engine, deactivate consumers
    }
}
```

The audio tap callback distributes each buffer to Shazam, Sound Analysis, and Speech Recognition simultaneously. This is the key parallelism point — one audio stream, three consumers.

### Integration with Existing Code

- **AppState** — Simplified. Keeps `hasCompletedOnboarding`. Permission tracking moves to `PermissionManager` inside `ServiceManager`.
- **ContentView** — Gets `@State private var serviceManager = ServiceManager()`. Passes to BottomNavBar for observe button binding.
- **GridController** — No changes. Still handles animations. ServiceManager tells it when to start/stop observe animation.
- **NavigationManager** — No changes.
- **BottomNavBar/ObserveButton** — Will bind to ServiceManager for press/release events and permission gating.

### What's Stubbed (for now)

- **ClaudeService** — Protocol + stub that returns mock culture map data. Real implementation in next phase.
- **DecisionRouter** — Not built yet. ServiceManager returns raw ObservationSignals; routing logic comes with Claude integration.
- **Onboarding UI** — Permission manager is real, but onboarding *views* are deferred (we build the manager first, wire up views after).

---

## Implementation Order

1. **Info.plist + entitlements** — Add all privacy usage descriptions
2. **ServiceConfiguration + data models** — ObservationSignals, AudioScene, etc.
3. **PermissionManager** — Real system permission calls, replaces PermissionStatus
4. **HapticService** — Simplest service, good pattern validator
5. **LocationService** — Already partially exists (reverse geocoding in ContentView)
6. **AudioService** — AVAudioEngine setup, shared buffer distribution
7. **ShazamService** — Consumes audio buffer, returns matches
8. **SoundAnalysisService** — Consumes audio buffer, classifies scene
9. **SpeechService** — Consumes audio buffer, transcribes speech
10. **MusicService** — MusicKit catalog queries + optional authorization
11. **ClaudeService** — Stub with protocol
12. **ServiceManager** — Wires everything together, exposes beginObservation/resolveObservation
13. **Wire to UI** — Connect ServiceManager to ContentView + ObserveButton

# Service Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the complete service layer — permission management, all Apple observation services (audio, Shazam, speech, sound analysis, location, haptics, MusicKit), a stubbed Claude service, and the central ServiceManager that coordinates them — wired into the existing UI.

**Architecture:** Centralized `ServiceManager` (`@Observable`, `@MainActor`) owns all services. `AudioService` manages the shared `AVAudioEngine` and fans out audio buffers to three consumers (Shazam, SoundAnalysis, Speech). Each service conforms to an `ObservationService` protocol. `PermissionManager` replaces the current `PermissionStatus` stub with real system calls. The existing Grid/Animation/Navigation layers remain untouched.

**Tech Stack:** Swift 6 concurrency (approachable mode, MainActor default), SwiftUI `@Observable`, AVAudioEngine, ShazamKit (`SHManagedSession`), SFSpeechRecognizer (on-device), SoundAnalysis (`SNAudioStreamAnalyzer`), CoreHaptics (`CHHapticEngine`), MusicKit, CoreLocation.

**Build verification:** Every task ends with an XcodeBuildMCP build to confirm compilation. No unit test target exists — validation is compile + run.

**Docs reference:** Design decisions documented in `.claude/anaspace-service-layer-design.md`. Observation logic spec in `.claude/anaspace-observe-logic-spec.md`.

---

### Task 1: Data Models & Configuration

**Files:**
- Create: `anaspace/Services/ServiceTypes.swift`

**Step 1: Create the service types file**

This file defines all shared types used across the service layer. Everything in one file to avoid circular dependencies.

```swift
import Foundation
import CoreLocation

// MARK: - Service Protocol

protocol ObservationService {
    var isAvailable: Bool { get }
    func activate() async throws
    func deactivate()
}

// MARK: - Observation Data

enum ObservationMode: String, Codable, Sendable {
    case tap
    case hold
}

enum AudioScene: String, Codable, Sendable {
    case music
    case speech
    case musicAndSpeech
    case singing
    case silence
    case ambient
    case unknown
}

struct ShazamResult: Sendable {
    let title: String
    let artist: String
    let album: String?
    let appleMusicID: String?
    let genres: [String]
    let releaseYear: Int?
    let artworkURL: URL?
    let confidence: Double
}

struct TranscriptResult: Sendable {
    let text: String
    let confidence: Double
    let isFinal: Bool
    var wordCount: Int { text.split(separator: " ").count }
}

struct LocationResult: Sendable {
    let coordinate: CLLocationCoordinate2D
    let placeName: String?
    let neighborhood: String?
    let city: String?
    let state: String?
    let country: String?
    let isoCountryCode: String?
}

struct ObservationSignals: Sendable {
    var shazamResult: ShazamResult?
    var transcript: TranscriptResult?
    var audioScene: AudioScene = .unknown
    var location: LocationResult?
    var timestamp: Date = .now
    var mode: ObservationMode = .tap
    var duration: TimeInterval = 0
    var resolutionTrigger: ResolutionTrigger = .hardTimeout
}

enum ResolutionTrigger: String, Codable, Sendable {
    case shazamMatch
    case silenceTimeout
    case hardTimeout
    case userRelease
}

// MARK: - Configuration

struct ServiceConfiguration: Sendable {
    var holdThresholdMs: Int = 500
    var hardTimeoutSeconds: Double = 10
    var silenceTimeoutSeconds: Double = 5
    var shazamConfidenceThreshold: Double = 0.7
    var speechConfidenceThreshold: Double = 0.4
    var commandMaxWords: Int = 20
    var discardShortTranscripts: Int = 3
    var locationCascadeMaxLevel: Int = 4
    var voiceOverridesShazam: Bool = true
    var lyricIdEnabled: Bool = true
}
```

**Step 2: Build to verify compilation**

Build with XcodeBuildMCP. Expected: success with no errors.

**Step 3: Commit**

```bash
git add anaspace/Services/ServiceTypes.swift
git commit -m "Add service layer data models and configuration types"
```

---

### Task 2: Permission Manager

**Files:**
- Create: `anaspace/Services/Permissions/PermissionManager.swift`
- Modify: `anaspace/Storage/AppState.swift` — remove `PermissionStatus` struct, add reference to PermissionManager

**Step 1: Create PermissionManager**

Real system permission calls for all five permissions. Uses `@Observable` so SwiftUI can react to changes. Persists permission awareness to LocalStore so we know whether we've asked before.

```swift
import Foundation
import AVFoundation
import CoreLocation
import Speech
import MusicKit
import UserNotifications

enum PermissionState: String, Codable, Sendable {
    case undetermined
    case granted
    case denied
}

@Observable @MainActor
final class PermissionManager {
    var microphone: PermissionState = .undetermined
    var location: PermissionState = .undetermined
    var speechRecognition: PermissionState = .undetermined
    var notifications: PermissionState = .undetermined
    var appleMusic: PermissionState = .undetermined

    /// All core permissions granted (mic + location + speech)
    var corePermissionsGranted: Bool {
        microphone == .granted && location == .granted && speechRecognition == .granted
    }

    private let locationDelegate = LocationPermissionDelegate()

    func refreshAll() async {
        microphone = mapAVStatus(AVAudioApplication.shared.recordPermission)
        location = mapCLStatus(CLLocationManager().authorizationStatus)
        speechRecognition = mapSpeechStatus(SFSpeechRecognizer.authorizationStatus())
        appleMusic = mapMusicStatus(MusicAuthorization.currentStatus)

        let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = mapNotifStatus(notifSettings.authorizationStatus)
    }

    // MARK: - Individual Requests

    func requestMicrophone() async -> PermissionState {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphone = granted ? .granted : .denied
        return microphone
    }

    func requestLocation() async -> PermissionState {
        let manager = CLLocationManager()
        manager.delegate = locationDelegate
        return await withCheckedContinuation { continuation in
            locationDelegate.onStatusChange = { [weak self] status in
                let state = self?.mapCLStatus(status) ?? .denied
                self?.location = state
                continuation.resume(returning: state)
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestSpeechRecognition() async -> PermissionState {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    let state = self?.mapSpeechStatus(status) ?? .denied
                    self?.speechRecognition = state
                    continuation.resume(returning: state)
                }
            }
        }
    }

    func requestNotifications() async -> PermissionState {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notifications = granted ? .granted : .denied
        } catch {
            notifications = .denied
        }
        return notifications
    }

    func requestAppleMusic() async -> PermissionState {
        let status = await MusicAuthorization.request()
        appleMusic = mapMusicStatus(status)
        return appleMusic
    }

    // MARK: - Status Mapping

    private func mapAVStatus(_ status: AVAudioApplication.recordPermission) -> PermissionState {
        switch status {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    private func mapCLStatus(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    private func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    private func mapMusicStatus(_ status: MusicAuthorization.Status) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }

    private func mapNotifStatus(_ status: UNAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .undetermined
        @unknown default: .undetermined
        }
    }
}

// MARK: - CLLocationManager Delegate

private final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    var onStatusChange: ((CLAuthorizationStatus) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        onStatusChange?(manager.authorizationStatus)
        onStatusChange = nil
    }
}
```

**Step 2: Update AppState**

Remove the old `PermissionStatus` struct and `PermissionState` enum from AppState.swift. AppState keeps `hasCompletedOnboarding` only. The `PermissionManager` lives in `ServiceManager` (Task 12) and gets injected into the environment from ContentView.

```swift
import Foundation

@Observable @MainActor
final class AppState {
    var hasCompletedOnboarding: Bool {
        didSet { LocalStore.shared.saveOnboardingComplete(hasCompletedOnboarding) }
    }

    init() {
        self.hasCompletedOnboarding = LocalStore.shared.loadOnboardingComplete()
    }
}
```

**Step 3: Build to verify compilation**

Build with XcodeBuildMCP. Expected: success. The old `currentPermissions` field is removed from AppState — verify nothing else referenced it.

**Step 4: Commit**

```bash
git add anaspace/Services/Permissions/PermissionManager.swift anaspace/Storage/AppState.swift
git commit -m "Add PermissionManager with real system permission calls"
```

---

### Task 3: Haptic Service

**Files:**
- Create: `anaspace/Services/Haptics/HapticService.swift`

**Step 1: Create HapticService**

Manages CHHapticEngine lifecycle and provides named patterns for the observation flow: idle pulse, music detected, speech detected, silence, success (Shazam match), and timeout.

```swift
import CoreHaptics

@Observable @MainActor
final class HapticService: ObservationService {
    private var engine: CHHapticEngine?
    private var activePlayer: CHHapticAdvancedPatternPlayer?
    private(set) var isAvailable: Bool = false

    init() {
        isAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func activate() async throws {
        guard isAvailable else { return }
        let engine = try CHHapticEngine()
        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                try? self?.engine?.start()
            }
        }
        engine.stoppedHandler = { _ in }
        try engine.start()
        self.engine = engine
    }

    func deactivate() {
        activePlayer?.cancel()
        activePlayer = nil
        engine?.stop()
        engine = nil
    }

    // MARK: - Observation Haptic Patterns

    /// Steady 1 Hz pulse — default observation heartbeat
    func playIdlePulse() {
        playLoopingPattern(intensity: 0.4, sharpness: 0.3, interval: 1.0)
    }

    /// 2 Hz pulse — music detected
    func playMusicPulse() {
        playLoopingPattern(intensity: 0.6, sharpness: 0.5, interval: 0.5)
    }

    /// Da-dum pattern — speech detected
    func playSpeechPattern() {
        guard let engine else { return }
        do {
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                ], relativeTime: 0.15),
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = 0.8
            activePlayer?.cancel()
            activePlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    /// Slow 0.5 Hz pulse — silence/ambient
    func playSilencePulse() {
        playLoopingPattern(intensity: 0.3, sharpness: 0.2, interval: 2.0)
    }

    /// Success burst — Shazam match
    func playSuccess() {
        activePlayer?.cancel()
        activePlayer = nil
        guard let engine else { return }
        do {
            let events = [
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ], relativeTime: 0),
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ], relativeTime: 0.1),
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    /// Timeout wind-down — observation ended without match
    func playTimeout() {
        activePlayer?.cancel()
        activePlayer = nil
        guard let engine else { return }
        do {
            let events = [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
                ], relativeTime: 0, duration: 0.3),
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    /// Stop any active pattern
    func stopPattern() {
        activePlayer?.cancel()
        activePlayer = nil
    }

    // MARK: - Private

    private func playLoopingPattern(intensity: Float, sharpness: Float, interval: TimeInterval) {
        guard let engine else { return }
        do {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = interval
            activePlayer?.cancel()
            activePlayer = player
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}
```

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 3: Commit**

```bash
git add anaspace/Services/Haptics/HapticService.swift
git commit -m "Add HapticService with observation haptic patterns"
```

---

### Task 4: Location Service

**Files:**
- Create: `anaspace/Services/Location/LocationService.swift`
- Modify: `anaspace/App/AnaspaceApp.swift` — remove inline `reverseGeocode` method (moved to service)

**Step 1: Create LocationService**

Wraps CLLocationManager for GPS coordinates and CLGeocoder for reverse geocoding. Produces `LocationResult`.

```swift
import CoreLocation

@Observable @MainActor
final class LocationService: ObservationService {
    private(set) var isAvailable: Bool = true
    private(set) var currentResult: LocationResult?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let delegate = LocationServiceDelegate()

    func activate() async throws {
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyBest

        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            delegate.onLocation = { location in
                continuation.resume(returning: location)
            }
            delegate.onError = { error in
                continuation.resume(throwing: error)
            }
            manager.requestLocation()
        }

        let placemark = try? await geocoder.reverseGeocodeLocation(location).first

        currentResult = LocationResult(
            coordinate: location.coordinate,
            placeName: placemark?.name,
            neighborhood: placemark?.subLocality,
            city: placemark?.locality,
            state: placemark?.administrativeArea,
            country: placemark?.country,
            isoCountryCode: placemark?.isoCountryCode
        )
    }

    func deactivate() {
        manager.stopUpdatingLocation()
        delegate.onLocation = nil
        delegate.onError = nil
    }

    /// Reverse geocode an arbitrary coordinate (used by map selection)
    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> LocationResult? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        return LocationResult(
            coordinate: coordinate,
            placeName: placemark?.name,
            neighborhood: placemark?.subLocality,
            city: placemark?.locality,
            state: placemark?.administrativeArea,
            country: placemark?.country,
            isoCountryCode: placemark?.isoCountryCode
        )
    }

    /// Format a LocationResult as a display label
    static func displayLabel(for result: LocationResult) -> String {
        let city = result.city ?? result.placeName ?? "UNKNOWN"
        let state = result.state ?? ""
        let country = result.isoCountryCode ?? ""
        if state.isEmpty {
            return "\(city) | \(country)".uppercased()
        }
        return "\(city), \(state) | \(country)".uppercased()
    }
}

// MARK: - Delegate

private final class LocationServiceDelegate: NSObject, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onError: ((Error) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocation?(location)
        onLocation = nil
        onError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error)
        onLocation = nil
        onError = nil
    }
}
```

**Step 2: Update ContentView to use LocationService for reverseGeocode**

In `AnaspaceApp.swift`, replace the inline `reverseGeocode` method with a call through `LocationService.reverseGeocode()`. This is a light refactor — the full ServiceManager wiring happens in Task 12. For now, just create a local `LocationService` instance and call it.

Replace the existing `reverseGeocode` method body:

```swift
private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
    Task {
        let service = LocationService()
        guard let result = await service.reverseGeocode(coordinate) else { return }
        homeRenderer?.locationLabel = LocationService.displayLabel(for: result)
        refreshGrid()
    }
}
```

**Step 3: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 4: Commit**

```bash
git add anaspace/Services/Location/LocationService.swift anaspace/App/AnaspaceApp.swift
git commit -m "Add LocationService with GPS and reverse geocoding"
```

---

### Task 5: Audio Service (shared engine)

**Files:**
- Create: `anaspace/Services/Audio/AudioService.swift`

**Step 1: Create AudioService**

Manages the shared AVAudioEngine. Installs a single tap on the input node and distributes audio buffers to registered consumers via a callback list. The three consumers (Shazam, SoundAnalysis, Speech) register themselves.

```swift
import AVFoundation

/// Callback type for audio buffer consumers
typealias AudioBufferHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

@Observable @MainActor
final class AudioService: ObservationService {
    private(set) var isAvailable: Bool = true
    private var engine: AVAudioEngine?
    private var consumers: [String: AudioBufferHandler] = [:]

    /// The audio format from the input node (available after activation)
    private(set) var inputFormat: AVAudioFormat?

    func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format

        let capturedConsumers = consumers
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
            for handler in capturedConsumers.values {
                handler(buffer, time)
            }
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func deactivate() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputFormat = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Register an audio buffer consumer before activation.
    /// Consumers must be registered before `activate()` is called.
    func registerConsumer(id: String, handler: @escaping AudioBufferHandler) {
        consumers[id] = handler
    }

    func removeConsumer(id: String) {
        consumers.removeValue(forKey: id)
    }

    func removeAllConsumers() {
        consumers.removeAll()
    }

    /// Re-install the tap with current consumers (for mid-session updates)
    func refreshTap() {
        guard let engine, engine.isRunning else { return }
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        let format = inputFormat ?? inputNode.outputFormat(forBus: 0)
        let capturedConsumers = consumers
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
            for handler in capturedConsumers.values {
                handler(buffer, time)
            }
        }
    }
}
```

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 3: Commit**

```bash
git add anaspace/Services/Audio/AudioService.swift
git commit -m "Add AudioService with shared AVAudioEngine and consumer dispatch"
```

---

### Task 6: Shazam Service

**Files:**
- Create: `anaspace/Services/Audio/ShazamService.swift`

**Step 1: Create ShazamService**

Uses `SHManagedSession` for modern async/await Shazam matching. Registers itself as an AudioService consumer.

```swift
import ShazamKit
import AVFoundation

@Observable @MainActor
final class ShazamService: ObservationService {
    private(set) var isAvailable: Bool = true
    private(set) var result: ShazamResult?
    private(set) var isMatching = false

    private var session: SHManagedSession?
    private var matchTask: Task<Void, Never>?

    weak var audioService: AudioService?

    func activate() async throws {
        result = nil
        isMatching = true

        let session = SHManagedSession()
        self.session = session

        // Register as audio consumer
        audioService?.registerConsumer(id: "shazam") { [weak session] buffer, time in
            session?.matchStreamingBuffer(buffer, at: time)
        }

        // Start listening for results
        matchTask = Task { [weak self] in
            guard let session = self?.session else { return }
            let shazamResult = await session.result()
            await MainActor.run {
                switch shazamResult {
                case .match(let match):
                    if let item = match.mediaItems.first {
                        self?.result = ShazamResult(
                            title: item.title ?? "Unknown",
                            artist: item.artist ?? "Unknown",
                            album: item.songs.first?.albumTitle,
                            appleMusicID: item.appleMusicID,
                            genres: item.genres,
                            releaseYear: item.songs.first?.releaseDate.map { Calendar.current.component(.year, from: $0) },
                            artworkURL: item.artworkURL,
                            confidence: 1.0
                        )
                    }
                case .noMatch:
                    self?.result = nil
                case .error:
                    self?.result = nil
                @unknown default:
                    self?.result = nil
                }
                self?.isMatching = false
            }
        }
    }

    func deactivate() {
        matchTask?.cancel()
        matchTask = nil
        audioService?.removeConsumer(id: "shazam")
        session?.cancel()
        session = nil
        isMatching = false
    }
}
```

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success. Note — `SHManagedSession` requires iOS 17+. `SHMediaItem.songs` and some properties may need adjustment based on exact API availability. Fix any compiler issues.

**Step 3: Commit**

```bash
git add anaspace/Services/Audio/ShazamService.swift
git commit -m "Add ShazamService using SHManagedSession async API"
```

---

### Task 7: Sound Analysis Service

**Files:**
- Create: `anaspace/Services/Audio/SoundAnalysisService.swift`

**Step 1: Create SoundAnalysisService**

Uses `SNAudioStreamAnalyzer` with `SNClassifySoundRequest` to classify audio as music, speech, silence, etc. Maps Apple's classification labels to our `AudioScene` enum.

```swift
import SoundAnalysis
import AVFoundation

@Observable @MainActor
final class SoundAnalysisService: ObservationService {
    private(set) var isAvailable: Bool = true
    private(set) var currentScene: AudioScene = .unknown

    private var analyzer: SNAudioStreamAnalyzer?
    private let observer = SoundAnalysisObserver()
    private let analysisQueue = DispatchQueue(label: "com.anaspace.soundanalysis")

    weak var audioService: AudioService?

    func activate() async throws {
        guard let format = audioService?.inputFormat else {
            throw ServiceError.audioFormatUnavailable
        }

        currentScene = .unknown
        let analyzer = SNAudioStreamAnalyzer(format: format)
        self.analyzer = analyzer

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 1000)
        request.overlapFactor = 0.5

        observer.onClassification = { [weak self] scene in
            Task { @MainActor in
                self?.currentScene = scene
            }
        }

        try analyzer.add(request, withObserver: observer)

        // Register as audio consumer
        audioService?.registerConsumer(id: "soundanalysis") { [weak analyzer, analysisQueue] buffer, time in
            analysisQueue.async {
                analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }
        }
    }

    func deactivate() {
        audioService?.removeConsumer(id: "soundanalysis")
        analyzer?.removeAllRequests()
        analyzer = nil
        currentScene = .unknown
    }
}

// MARK: - Observer

private final class SoundAnalysisObserver: NSObject, SNResultsObserving {
    var onClassification: ((AudioScene) -> Void)?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        guard let top = classification.classifications.first else { return }

        let scene = mapLabel(top.identifier, confidence: top.confidence)
        onClassification?(scene)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}

    private func mapLabel(_ label: String, confidence: Double) -> AudioScene {
        guard confidence > 0.3 else { return .ambient }

        let lowered = label.lowercased()
        if lowered.contains("music") && lowered.contains("speech") { return .musicAndSpeech }
        if lowered.contains("music") || lowered.contains("singing") { return .music }
        if lowered.contains("speech") || lowered.contains("conversation") { return .speech }
        if lowered.contains("silence") { return .silence }
        return .ambient
    }
}

// MARK: - Service Error

enum ServiceError: Error {
    case audioFormatUnavailable
}
```

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success. The `SNClassifySoundRequest(classifierIdentifier: .version1)` initializer is iOS 15+. Adjust if the API surface differs.

**Step 3: Commit**

```bash
git add anaspace/Services/Audio/SoundAnalysisService.swift
git commit -m "Add SoundAnalysisService for audio scene classification"
```

---

### Task 8: Speech Service

**Files:**
- Create: `anaspace/Services/Audio/SpeechService.swift`

**Step 1: Create SpeechService**

Wraps `SFSpeechRecognizer` with `SFSpeechAudioBufferRecognitionRequest` for on-device real-time transcription. Receives audio buffers from AudioService.

```swift
import Speech
import AVFoundation

@Observable @MainActor
final class SpeechService: ObservationService {
    private(set) var isAvailable: Bool = false
    private(set) var currentTranscript: TranscriptResult?
    private(set) var isTranscribing = false

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    weak var audioService: AudioService?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        isAvailable = recognizer?.isAvailable ?? false
    }

    func activate() async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ServiceError.speechRecognizerUnavailable
        }

        currentTranscript = nil
        isTranscribing = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition when available
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    let transcript = TranscriptResult(
                        text: result.bestTranscription.formattedString,
                        confidence: Double(result.bestTranscription.segments.last?.confidence ?? 0),
                        isFinal: result.isFinal
                    )
                    self?.currentTranscript = transcript
                    if result.isFinal {
                        self?.isTranscribing = false
                    }
                }
                if error != nil {
                    self?.isTranscribing = false
                }
            }
        }

        // Register as audio consumer
        audioService?.registerConsumer(id: "speech") { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    func deactivate() {
        audioService?.removeConsumer(id: "speech")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
    }
}

extension ServiceError {
    static let speechRecognizerUnavailable = ServiceError.audioFormatUnavailable
    // TODO: Add proper error case in ServiceError enum
}
```

Note: The `ServiceError` extension is a temporary workaround. In Step 2, add a proper case to the enum in `SoundAnalysisService.swift`:

Update `ServiceError` in `SoundAnalysisService.swift` to include the speech case:

```swift
enum ServiceError: Error {
    case audioFormatUnavailable
    case speechRecognizerUnavailable
}
```

And remove the extension from SpeechService.

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success. Fix any compilation issues with `SFSpeechRecognizer` API.

**Step 3: Commit**

```bash
git add anaspace/Services/Audio/SpeechService.swift anaspace/Services/Audio/SoundAnalysisService.swift
git commit -m "Add SpeechService for on-device real-time transcription"
```

---

### Task 9: Music Service

**Files:**
- Create: `anaspace/Services/Music/MusicService.swift`

**Step 1: Create MusicService**

Wraps MusicKit for catalog lookups. Enriches Shazam results with genre, editorial notes, and related artists. Supports both authorized and unauthorized paths.

```swift
import MusicKit

@Observable @MainActor
final class MusicService: ObservationService {
    private(set) var isAvailable: Bool = false
    var isAuthorized: Bool { MusicAuthorization.currentStatus == .authorized }

    func activate() async throws {
        isAvailable = true
    }

    func deactivate() {
        isAvailable = false
    }

    /// Enrich a Shazam result with MusicKit catalog data
    func enrich(shazamResult: ShazamResult) async -> MusicEnrichment? {
        // Catalog search works without subscription (just needs authorization)
        guard isAuthorized else { return nil }

        do {
            var request = MusicCatalogSearchRequest(
                term: "\(shazamResult.artist) \(shazamResult.title)",
                types: [Song.self, Artist.self]
            )
            request.limit = 5

            let response = try await request.response()

            let song = response.songs.first
            let artist = response.artists.first

            return MusicEnrichment(
                genre: song?.genreNames.first,
                allGenres: song?.genreNames ?? [],
                editorialNotes: artist?.editorialNotes?.standard,
                releaseDate: song?.releaseDate,
                appleMusicURL: song?.url,
                artistURL: artist?.url
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Enrichment Data

struct MusicEnrichment: Sendable {
    let genre: String?
    let allGenres: [String]
    let editorialNotes: String?
    let releaseDate: Date?
    let appleMusicURL: URL?
    let artistURL: URL?
}
```

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success. MusicKit types may need adjustment based on exact API.

**Step 3: Commit**

```bash
git add anaspace/Services/Music/MusicService.swift
git commit -m "Add MusicService for MusicKit catalog enrichment"
```

---

### Task 10: Claude Service (Stub)

**Files:**
- Create: `anaspace/Services/AI/ClaudeService.swift`
- Modify: `Secrets.xcconfig` — add `CLAUDE_API_KEY` placeholder
- Modify: `Secrets.xcconfig.example` — add `CLAUDE_API_KEY` placeholder
- Modify: `anaspace/Info.plist` — add `CLAUDE_API_KEY` reference

**Step 1: Create stubbed ClaudeService**

A protocol-first stub. Defines the interface for culture map generation. The real implementation comes in the next phase.

```swift
import Foundation

/// Model tier for Claude API calls
enum ClaudeModel: String, Sendable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-5-20250929"
}

/// Stubbed culture map response
struct CultureMapResponse: Sendable {
    let subject: String
    let subjectType: String
    let place: String
    let year: Int
    let narrative: String
    let connections: [CultureConnection]
}

struct CultureConnection: Sendable {
    let name: String
    let relationship: String  // "influenced", "contemporary", "collaborator", etc.
    let relevance: Double     // 0.0 - 1.0
}

@Observable @MainActor
final class ClaudeService: ObservationService {
    private(set) var isAvailable: Bool = true
    var apiKey: String?

    func activate() async throws {
        // Load API key from bundle
        apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String
        isAvailable = apiKey != nil && apiKey?.isEmpty == false
    }

    func deactivate() {}

    /// Build a culture map from observation signals.
    /// STUB: Returns mock data. Real implementation in next phase.
    func buildCultureMap(from signals: ObservationSignals) async throws -> CultureMapResponse {
        // Simulate network delay
        try await Task.sleep(for: .seconds(1))

        let subject = signals.shazamResult?.artist ?? signals.transcript?.text ?? "Unknown"
        let year = signals.shazamResult?.releaseYear ?? Calendar.current.component(.year, from: signals.timestamp)
        let place = signals.location?.city ?? "Unknown"

        return CultureMapResponse(
            subject: subject,
            subjectType: "person",
            place: place,
            year: year,
            narrative: "A cultural exploration of \(subject) in \(place), \(year).",
            connections: [
                CultureConnection(name: "Connection 1", relationship: "influenced", relevance: 0.9),
                CultureConnection(name: "Connection 2", relationship: "contemporary", relevance: 0.7),
                CultureConnection(name: "Connection 3", relationship: "collaborator", relevance: 0.6),
            ]
        )
    }
}
```

**Step 2: Update Secrets.xcconfig and example**

Add to `Secrets.xcconfig`:
```
CLAUDE_API_KEY =
```

Add to `Secrets.xcconfig.example`:
```
CLAUDE_API_KEY = your_claude_api_key_here
```

**Step 3: Update Info.plist**

Add `CLAUDE_API_KEY` key with value `$(CLAUDE_API_KEY)` to `anaspace/Info.plist`, same pattern as Mapbox token.

**Step 4: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 5: Commit**

```bash
git add anaspace/Services/AI/ClaudeService.swift anaspace/Info.plist Secrets.xcconfig.example
git commit -m "Add stubbed ClaudeService and Claude API key configuration"
```

Note: Do NOT commit `Secrets.xcconfig` itself — it's gitignored.

---

### Task 11: Add Speech Recognition Usage Description

**Files:**
- Modify: Xcode project build settings (via XcodeBuildMCP or project file)

**Step 1: Add missing plist key**

The project already has `NSMicrophoneUsageDescription`, `NSLocationWhenInUseUsageDescription`, and `NSAppleMusicUsageDescription` configured in build settings. We need to add `NSSpeechRecognitionUsageDescription`.

This is set via `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` in the Xcode project build settings. Add it to the project's build configuration.

Check the `.pbxproj` file for the existing INFOPLIST_KEY entries and add the speech recognition one in the same section.

Value: `"Anaspace uses speech recognition to understand your voice commands for cultural exploration."`

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 3: Commit**

```bash
git add anaspace.xcodeproj/project.pbxproj
git commit -m "Add NSSpeechRecognitionUsageDescription to build settings"
```

---

### Task 12: Service Manager

**Files:**
- Create: `anaspace/Services/ServiceManager.swift`

**Step 1: Create ServiceManager**

The central coordinator. Owns all services, wires audio consumers, and manages observation sessions.

```swift
import Foundation

@Observable @MainActor
final class ServiceManager {
    // Services
    let permissions = PermissionManager()
    let haptics = HapticService()
    let location = LocationService()
    let audio = AudioService()
    let shazam = ShazamService()
    let soundAnalysis = SoundAnalysisService()
    let speech = SpeechService()
    let music = MusicService()
    let claude = ClaudeService()

    // Configuration
    let config = ServiceConfiguration()

    // Observation state
    private(set) var isObserving = false
    private(set) var currentSignals: ObservationSignals?
    private var observationStart: Date?
    private var observationTask: Task<Void, Never>?
    private var holdMode = false

    init() {
        // Wire audio consumers to shared audio service
        shazam.audioService = audio
        soundAnalysis.audioService = audio
        speech.audioService = audio
    }

    /// Call on app launch to sync permission state
    func refreshPermissions() async {
        await permissions.refreshAll()
    }

    // MARK: - Observation Lifecycle

    /// Begin an observation. All Group 1 services activate in parallel.
    func beginObservation() async {
        guard !isObserving else { return }
        isObserving = true
        holdMode = false
        observationStart = .now
        currentSignals = ObservationSignals()

        // Activate haptics first for immediate feedback
        try? await haptics.activate()
        haptics.playIdlePulse()

        // Activate all Group 1 services in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await self.location.activate() }
            group.addTask { try? await self.audio.activate() }
        }

        // Audio consumers need the engine running first
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await self.shazam.activate() }
            group.addTask { try? await self.soundAnalysis.activate() }
            group.addTask { try? await self.speech.activate() }
        }

        // Start monitoring for resolution triggers (tap mode)
        observationTask = Task {
            await monitorObservation()
        }
    }

    /// Signal that the user is holding (called at 500ms threshold)
    func setHoldMode() {
        holdMode = true
    }

    /// End observation (called on button release in hold mode, or by resolution triggers in tap mode)
    func endObservation() {
        guard isObserving else { return }
        observationTask?.cancel()
        collectSignals()
        deactivateAll()
        isObserving = false
    }

    // MARK: - Private

    private func monitorObservation() async {
        let startTime = Date.now

        // Poll for resolution triggers
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))

            let elapsed = Date.now.timeIntervalSince(startTime)

            // Update haptics based on audio scene
            updateHaptics()

            // Check: Shazam match
            if shazam.result != nil {
                haptics.playSuccess()
                try? await Task.sleep(for: .milliseconds(300))
                currentSignals?.resolutionTrigger = .shazamMatch
                endObservation()
                return
            }

            // Check: Hard timeout (tap mode only)
            if !holdMode && elapsed >= config.hardTimeoutSeconds {
                haptics.playTimeout()
                currentSignals?.resolutionTrigger = .hardTimeout
                endObservation()
                return
            }

            // Check: Silence timeout (tap mode only)
            if !holdMode && soundAnalysis.currentScene == .silence {
                // TODO: Track continuous silence duration
                if elapsed >= config.silenceTimeoutSeconds {
                    haptics.playTimeout()
                    currentSignals?.resolutionTrigger = .silenceTimeout
                    endObservation()
                    return
                }
            }
        }
    }

    private func updateHaptics() {
        switch soundAnalysis.currentScene {
        case .music, .musicAndSpeech:
            haptics.playMusicPulse()
        case .speech:
            haptics.playSpeechPattern()
        case .silence:
            haptics.playSilencePulse()
        case .singing, .ambient, .unknown:
            break // keep current pattern
        }
    }

    private func collectSignals() {
        currentSignals?.shazamResult = shazam.result
        currentSignals?.transcript = speech.currentTranscript
        currentSignals?.audioScene = soundAnalysis.currentScene
        currentSignals?.location = location.currentResult
        currentSignals?.timestamp = .now
        currentSignals?.mode = holdMode ? .hold : .tap
        currentSignals?.duration = observationStart.map { Date.now.timeIntervalSince($0) } ?? 0

        // Discard short transcripts per config
        if let transcript = currentSignals?.transcript,
           transcript.wordCount < config.discardShortTranscripts {
            currentSignals?.transcript = nil
        }
    }

    private func deactivateAll() {
        haptics.stopPattern()
        shazam.deactivate()
        soundAnalysis.deactivate()
        speech.deactivate()
        audio.deactivate()
        location.deactivate()
        haptics.deactivate()
    }
}
```

**Step 2: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 3: Commit**

```bash
git add anaspace/Services/ServiceManager.swift
git commit -m "Add ServiceManager coordinating all observation services"
```

---

### Task 13: Wire ServiceManager to UI

**Files:**
- Modify: `anaspace/App/AnaspaceApp.swift` — add ServiceManager, update observe button binding
- Modify: `anaspace/Navigation/BottomNavBar.swift` — support press-and-hold gesture for observe button

**Step 1: Update ContentView to use ServiceManager**

Add `@State private var serviceManager = ServiceManager()` to ContentView. Replace the current observe tap handler with ServiceManager calls. Remove the local `LocationService` from Task 4 and use `serviceManager.location` instead.

In ContentView, update:

1. Add `serviceManager` state
2. Update `onObserveTap` to call `serviceManager.beginObservation()`
3. Update `reverseGeocode` to use `serviceManager.location.reverseGeocode()`
4. Pass ServiceManager's `isObserving` to GridController

```swift
@State private var serviceManager = ServiceManager()
```

The observe tap handler becomes:

```swift
onObserveTap: {
    if serviceManager.isObserving {
        serviceManager.endObservation()
    } else {
        Task {
            await serviceManager.beginObservation()
        }
        controller.triggerObserve { grid in
            populateGrid(grid)
        }
    }
}
```

And `reverseGeocode`:

```swift
private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
    Task {
        guard let result = await serviceManager.location.reverseGeocode(coordinate) else { return }
        homeRenderer?.locationLabel = LocationService.displayLabel(for: result)
        refreshGrid()
    }
}
```

Add permission refresh on appear:

```swift
.task {
    await serviceManager.refreshPermissions()
}
```

**Step 2: Update ObserveButton for press-and-hold**

Modify `ObserveButton` in `BottomNavBar.swift` to support long press detection. Add an `onPressStart` and `onPressEnd` callback. After 500ms of holding, call `serviceManager.setHoldMode()`. On release, call the appropriate end handler.

Add callbacks to ObserveButton:

```swift
struct ObserveButton: View {
    let isObserving: Bool
    let navDark: Color
    let bg: Color
    let red: Color
    let onTap: () -> Void
    var onHoldStart: () -> Void = {}
    var onHoldEnd: () -> Void = {}
    // ... existing code ...
}
```

Update the gesture to detect hold vs tap:

```swift
.gesture(
    DragGesture(minimumDistance: 0)
        .onChanged { _ in
            if !isPressed {
                isPressed = true
                onHoldStart()
            }
        }
        .onEnded { _ in
            isPressed = false
            onHoldEnd()
        }
)
```

The tap vs. hold distinction is managed by `ServiceManager` — it starts observation immediately on press, then `setHoldMode()` is called from a timer at 500ms. On release, `endObservation()` resolves appropriately.

**Step 3: Build to verify**

Build with XcodeBuildMCP. Expected: success.

**Step 4: Run on simulator**

Build and run on iPhone 16 Pro simulator to verify the app launches without crashes. The services won't produce real results in simulator (no microphone, Shazam, etc.) but the lifecycle should work.

**Step 5: Commit**

```bash
git add anaspace/App/AnaspaceApp.swift anaspace/Navigation/BottomNavBar.swift
git commit -m "Wire ServiceManager to UI with observe button integration"
```

---

## Summary

| Task | Component | Creates | Modifies |
|------|-----------|---------|----------|
| 1 | Data Models | `Services/ServiceTypes.swift` | — |
| 2 | Permissions | `Services/Permissions/PermissionManager.swift` | `Storage/AppState.swift` |
| 3 | Haptics | `Services/Haptics/HapticService.swift` | — |
| 4 | Location | `Services/Location/LocationService.swift` | `App/AnaspaceApp.swift` |
| 5 | Audio Engine | `Services/Audio/AudioService.swift` | — |
| 6 | Shazam | `Services/Audio/ShazamService.swift` | — |
| 7 | Sound Analysis | `Services/Audio/SoundAnalysisService.swift` | — |
| 8 | Speech | `Services/Audio/SpeechService.swift` | `SoundAnalysisService.swift` |
| 9 | MusicKit | `Services/Music/MusicService.swift` | — |
| 10 | Claude (stub) | `Services/AI/ClaudeService.swift` | `Info.plist`, `Secrets.xcconfig.example` |
| 11 | Plist keys | — | `project.pbxproj` |
| 12 | ServiceManager | `Services/ServiceManager.swift` | — |
| 13 | UI wiring | — | `AnaspaceApp.swift`, `BottomNavBar.swift` |

**Total new files:** 11
**Modified files:** 5
**Estimated commits:** 13

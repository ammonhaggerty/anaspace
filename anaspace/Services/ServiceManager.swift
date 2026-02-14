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
        // Wire all audio consumers to shared audio service
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
        print("[Observe] BEGIN")

        // Activate haptics first for immediate feedback
        do {
            try await haptics.activate()
            print("[Observe] Haptics: activated")
        } catch {
            print("[Observe] Haptics: FAILED - \(error)")
        }
        haptics.playIdlePulse()

        // Activate location and audio in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    try await self.location.activate()
                } catch {
                    print("[Observe] Location error: \(error)")
                }
            }
            group.addTask {
                do {
                    try await self.audio.activate()
                } catch {
                    print("[Observe] Audio error: \(error)")
                }
            }
        }
        print("[Observe] Location: \(location.currentResult?.city ?? "none")")
        print("[Observe] Audio: \(audio.inputFormat != nil ? "ready" : "FAILED")")

        // Audio consumers need the engine running first
        // All three register as AudioService consumers in their activate()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await self.shazam.activate() }
            group.addTask { try? await self.soundAnalysis.activate() }
            group.addTask { try? await self.speech.activate() }
        }

        // Refresh the audio tap so newly registered consumers receive buffers
        audio.refreshTap()

        print("[Observe] Shazam: \(shazam.isMatching ? "listening" : "not active")")
        print("[Observe] SoundAnalysis: \(soundAnalysis.currentScene.rawValue)")
        print("[Observe] Speech: \(speech.isTranscribing ? "transcribing" : "not active")")
        print("[Observe] All services ready, monitoring...")

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
        if holdMode {
            currentSignals?.resolutionTrigger = .userRelease
        }
        collectSignals()
        deactivateAll()
        isObserving = false
        print("[Observe] END - trigger: \(currentSignals?.resolutionTrigger.rawValue ?? "none"), duration: \(String(format: "%.1f", currentSignals?.duration ?? 0))s")
        if let signals = currentSignals {
            print("[Observe]   shazam: \(signals.shazamResult?.title ?? "none")")
            print("[Observe]   speech: \(signals.transcript?.text ?? "none")")
            print("[Observe]   scene:  \(signals.audioScene.rawValue)")
            print("[Observe]   location: \(signals.location?.city ?? "none")")
        }
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
            if let match = shazam.result {
                print("[Observe] Shazam MATCH: \(match.title) by \(match.artist)")
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

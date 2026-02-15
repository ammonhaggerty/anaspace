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

    // Progress — single observable surface for the UI
    let progress = ObservationProgress()

    // Task handles for cancellation
    private var captureTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var shazamTimeoutTask: Task<Void, Never>?
    private var claudeTask: Task<Void, Never>?
    private var lateShazamTask: Task<Void, Never>?

    // Internal state
    private var captureStartTime: Date?

    init() {
        shazam.audioService = audio
        soundAnalysis.audioService = audio
        speech.audioService = audio
    }

    /// Call on app launch to sync permission state
    func refreshPermissions() async {
        await permissions.refreshAll()
    }

    // MARK: - Public API

    /// Begin capture — always starts as tap mode.
    func beginCapture() async {
        // Cancel any in-flight observation
        cancelAllTasks()
        deactivateAll()
        progress.reset()

        captureStartTime = .now
        progress.startCaptureTiming()
        progress.transitionTo(.capturing)
        progress.logEvent("Capture started")

        // Haptics first for immediate feedback
        do {
            try await haptics.activate()
            haptics.playIdlePulse()
        } catch {
            progress.logEvent("Haptics failed: \(error)")
        }

        guard progress.phase == .capturing else { return }

        // Location — fire-and-forget, don't block audio pipeline
        locationTask = Task {
            do {
                try await self.location.activate()
                guard self.progress.phase == .capturing || self.progress.phase == .processing else { return }
                self.progress.setLocation(self.location.currentResult)
            } catch {
                if !(error is CancellationError) {
                    self.progress.logEvent("Location error: \(error)")
                }
            }
        }

        // Audio engine — must be up before consumers
        do {
            try await audio.activate()
        } catch {
            progress.logEvent("Audio error: \(error)")
        }

        guard progress.phase == .capturing else { return }

        // Audio consumers: Shazam + SoundAnalysis (no Speech yet in tap mode)
        try? await shazam.activate()
        progress.setShazamActive(shazam.isMatching)

        guard progress.phase == .capturing else { return }

        try? await soundAnalysis.activate()
        progress.setSoundAnalysisActive(true)

        // Refresh audio tap for newly registered consumers
        audio.refreshTap()

        guard progress.phase == .capturing else { return }

        // Start Shazam timeout (10s from press, regardless of mode)
        shazamTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(config.shazamTimeoutSeconds))
            if !Task.isCancelled {
                progress.logEvent("Shazam timeout reached")
                progress.setShazamActive(false)
                shazam.deactivate()
            }
        }

        // Start tap-mode monitor loop
        monitorTask = Task {
            await monitorTapMode()
        }
    }

    /// Called at 300ms threshold — upgrades tap to hold, adds Speech.
    func upgradeToHold() async {
        guard progress.phase == .capturing, progress.mode == .tap else { return }

        // Cancel tap-mode monitor
        monitorTask?.cancel()
        monitorTask = nil

        progress.setMode(.hold)
        progress.logEvent("Upgraded to hold mode")

        // Activate speech
        do {
            try await speech.activate()
            guard progress.phase == .capturing else { return }
            progress.setSpeechActive(speech.isTranscribing)
        } catch {
            progress.logEvent("Speech error: \(error)")
        }

        guard progress.phase == .capturing else { return }

        // Refresh audio tap so Speech receives buffers
        audio.refreshTap()

        // Start hold monitor (updates transcript, checks Shazam)
        monitorTask = Task {
            await monitorHoldMode()
        }
    }

    /// Called on hold release, or internally on tap resolution.
    func endCapture() {
        guard progress.phase == .capturing else { return }

        // Stop monitor
        monitorTask?.cancel()
        monitorTask = nil

        // Collect final signals
        collectSignals()

        // Stop audio consumers
        speech.deactivate()
        progress.setSpeechActive(false)
        soundAnalysis.deactivate()
        progress.setSoundAnalysisActive(false)
        haptics.stopPattern()
        audio.deactivate()

        let elapsed = captureStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
        let shazamTimeRemaining = config.shazamTimeoutSeconds - elapsed

        progress.transitionTo(.processing)
        progress.logEvent("Capture ended, duration: \(String(format: "%.1f", elapsed))s")

        // Determine trigger
        let trigger: ResolutionTrigger = progress.mode == .hold ? .userRelease : .hardTimeout

        // Fire Claude request
        processResults(trigger: trigger)

        // In hold mode, check if Shazam still has time for a late match
        if progress.mode == .hold && shazamTimeRemaining > 0 && progress.shazamResult == nil {
            progress.logEvent("Monitoring for late Shazam (\(String(format: "%.1f", shazamTimeRemaining))s remaining)")
            lateShazamTask = Task {
                await monitorLateShazam()
            }
        }
    }

    // MARK: - Tap Mode Monitor

    private func monitorTapMode() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, progress.phase == .capturing else { return }

            progress.updateElapsed()
            updateHaptics()

            // Check: Shazam match
            if let match = shazam.result {
                progress.setShazamResult(match)
                haptics.playSuccess()
                try? await Task.sleep(for: .milliseconds(300))
                collectSignals()

                // Stop audio + services
                speech.deactivate()
                soundAnalysis.deactivate()
                haptics.stopPattern()
                audio.deactivate()

                progress.transitionTo(.processing)
                processResults(trigger: .shazamMatch)
                return
            }

            // Check: Hard timeout (tap mode uses shazam timeout as hard limit)
            if progress.elapsed >= config.shazamTimeoutSeconds {
                haptics.playTimeout()
                collectSignals()

                speech.deactivate()
                soundAnalysis.deactivate()
                haptics.stopPattern()
                audio.deactivate()

                progress.transitionTo(.processing)
                processResults(trigger: .hardTimeout)
                return
            }

            // Update scene
            progress.setAudioScene(soundAnalysis.currentScene)
        }
    }

    // MARK: - Hold Mode Monitor

    private func monitorHoldMode() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, progress.phase == .capturing else { return }

            progress.updateElapsed()
            updateHaptics()

            // Update live transcript
            if let transcript = speech.currentTranscript {
                progress.setTranscript(transcript)
            }

            // Check for Shazam match during hold (retain it)
            if progress.shazamResult == nil, let match = shazam.result {
                progress.setShazamResult(match)
                haptics.playSuccess()
            }

            // Update scene
            progress.setAudioScene(soundAnalysis.currentScene)
        }
    }

    // MARK: - Result Processing

    private func processResults(trigger: ResolutionTrigger) {
        let signals = ObservationSignals(
            shazamResult: progress.shazamResult,
            transcript: progress.transcript,
            audioScene: progress.audioScene,
            location: progress.location,
            timestamp: .now,
            mode: progress.mode,
            duration: progress.elapsed,
            resolutionTrigger: trigger
        )

        // Log what we're sending
        progress.logEvent("Claude signals — shazam: \(signals.shazamResult?.title ?? "none"), transcript: \(signals.transcript?.text ?? "none"), location: \(signals.location?.city ?? "none")")
        progress.setClaudeProcessing(true)
        progress.logEvent("Sending to Claude (trigger: \(trigger.rawValue))")

        claudeTask?.cancel()
        claudeTask = Task {
            do {
                try await claude.activate()
                progress.logEvent("Claude API key: \(claude.isAvailable ? "available" : "MISSING")")
                guard claude.isAvailable else {
                    progress.logEvent("Claude skipped — no API key")
                    progress.setClaudeProcessing(false)
                    resolve()
                    return
                }
                let result = try await claude.processObservation(from: signals)
                guard !Task.isCancelled else { return }
                progress.setLatestResult(result)
                progress.setClaudeProcessing(false)

                // If no late Shazam pending, resolve now
                if lateShazamTask == nil {
                    resolve()
                }
            } catch {
                progress.logEvent("Claude error: \(error)")
                progress.setClaudeProcessing(false)
                resolve()
            }
        }
    }

    // MARK: - Late Shazam Monitor

    private func monitorLateShazam() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            // Shazam timed out — done
            if !shazam.isMatching {
                progress.logEvent("Late Shazam: timed out, no match")
                // If Claude is done too, resolve
                if !progress.isClaudeProcessing {
                    resolve()
                }
                return
            }

            // Late Shazam match!
            if let match = shazam.result, progress.shazamResult == nil {
                progress.setShazamResult(match)
                progress.markResultSuperseded()
                progress.logEvent("Late Shazam match: \(match.title)")

                // Fire new Claude request with merged context
                let mergedSignals = ObservationSignals(
                    shazamResult: match,
                    transcript: progress.transcript,
                    audioScene: progress.audioScene,
                    location: progress.location,
                    timestamp: .now,
                    mode: progress.mode,
                    duration: progress.elapsed,
                    resolutionTrigger: .shazamMatch
                )

                progress.setClaudeProcessing(true)
                claudeTask?.cancel()
                claudeTask = Task {
                    do {
                        let result = try await claude.processObservation(from: mergedSignals)
                        guard !Task.isCancelled else { return }
                        progress.setLatestResult(result, superseded: false)
                    } catch {
                        progress.logEvent("Claude error (late Shazam): \(error)")
                    }
                    progress.setClaudeProcessing(false)
                    resolve()
                }
                return
            }
        }
    }

    // MARK: - Resolution

    private func resolve() {
        cancelAllTasks()
        deactivateAll()

        progress.setShazamActive(false)
        progress.setSpeechActive(false)
        progress.setSoundAnalysisActive(false)
        progress.transitionTo(.resolved)
        progress.logEvent("Observation complete")
    }

    // MARK: - Helpers

    private func updateHaptics() {
        switch soundAnalysis.currentScene {
        case .music, .musicAndSpeech:
            haptics.playMusicPulse()
        case .speech:
            haptics.playSpeechPattern()
        case .silence:
            haptics.playSilencePulse()
        case .singing, .ambient, .unknown:
            break
        }
    }

    private func collectSignals() {
        if progress.shazamResult == nil, let result = shazam.result {
            progress.setShazamResult(result)
        }
        if let transcript = speech.currentTranscript {
            if transcript.wordCount >= config.discardShortTranscripts {
                progress.setTranscript(transcript)
            } else {
                progress.logEvent("Transcript discarded (too short: \(transcript.wordCount) words): \"\(transcript.text)\"")
            }
        }
        progress.setAudioScene(soundAnalysis.currentScene)
        if progress.location == nil {
            progress.setLocation(location.currentResult)
        }
    }

    private func deactivateAll() {
        shazam.deactivate()
        soundAnalysis.deactivate()
        speech.deactivate()
        audio.deactivate()
        location.deactivate()
        haptics.stopPattern()
        haptics.deactivate()
    }

    private func cancelAllTasks() {
        captureTask?.cancel()
        captureTask = nil
        locationTask?.cancel()
        locationTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        shazamTimeoutTask?.cancel()
        shazamTimeoutTask = nil
        claudeTask?.cancel()
        claudeTask = nil
        lateShazamTask?.cancel()
        lateShazamTask = nil
    }
}

import CoreHaptics

// MARK: - Haptic Service

@Observable
@MainActor
final class HapticService: ObservationService {

    // MARK: - Properties

    private var engine: CHHapticEngine?
    private var activePlayer: CHHapticAdvancedPatternPlayer?
    private(set) var isAvailable: Bool

    // MARK: - Init

    init() {
        isAvailable = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    // MARK: - ObservationService Conformance

    func activate() async throws {
        guard isAvailable else { return }

        let engine = try CHHapticEngine()

        engine.resetHandler = { [weak self] in
            Task { @MainActor in
                do {
                    try await self?.engine?.start()
                } catch {
                    // Engine restart failed — haptics unavailable until next activate
                }
            }
        }

        engine.stoppedHandler = { [weak self] reason in
            Task { @MainActor in
                self?.engine = nil
                self?.activePlayer = nil
            }
        }

        try await engine.start()
        self.engine = engine
    }

    func deactivate() {
        do {
            try activePlayer?.cancel()
        } catch {}
        activePlayer = nil
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    // MARK: - Looping Pattern Methods

    /// Default observation heartbeat: 1 Hz transient loop, intensity 0.4, sharpness 0.3
    func playIdlePulse() {
        playLoopingPattern(intensity: 0.4, sharpness: 0.3, interval: 1.0)
    }

    /// Music detected: 2 Hz transient loop, intensity 0.6, sharpness 0.5
    func playMusicPulse() {
        playLoopingPattern(intensity: 0.6, sharpness: 0.5, interval: 0.5)
    }

    /// Speech detected: da-dum pattern — two transients at 0.15s offset, looped at 0.8s interval
    func playSpeechPattern() {
        guard let engine else { return }

        do {
            try activePlayer?.cancel()
            activePlayer = nil

            let transient1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                ],
                relativeTime: 0
            )

            let transient2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: 0.15
            )

            let pattern = try CHHapticPattern(events: [transient1, transient2], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = 0.8
            try player.start(atTime: CHHapticTimeImmediate)
            activePlayer = player
        } catch {
            // Haptic failure is non-fatal
        }
    }

    /// Silence/ambient: 0.5 Hz transient loop, intensity 0.3, sharpness 0.2
    func playSilencePulse() {
        playLoopingPattern(intensity: 0.3, sharpness: 0.2, interval: 2.0)
    }

    // MARK: - One-Shot Pattern Methods

    /// Shazam match: two quick transients
    func playSuccess() {
        guard let engine else { return }

        do {
            try activePlayer?.cancel()
            activePlayer = nil

            let transient1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                ],
                relativeTime: 0
            )

            let transient2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ],
                relativeTime: 0.1
            )

            let pattern = try CHHapticPattern(events: [transient1, transient2], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptic failure is non-fatal
        }
    }

    /// Observation timeout: single continuous event 0.3s
    func playTimeout() {
        guard let engine else { return }

        do {
            try activePlayer?.cancel()
            activePlayer = nil

            let continuous = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
                ],
                relativeTime: 0,
                duration: 0.3
            )

            let pattern = try CHHapticPattern(events: [continuous], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Haptic failure is non-fatal
        }
    }

    /// Cancels the active looping player
    func stopPattern() {
        do {
            try activePlayer?.cancel()
        } catch {}
        activePlayer = nil
    }

    // MARK: - Private Helper

    private func playLoopingPattern(intensity: Float, sharpness: Float, interval: TimeInterval) {
        guard let engine else { return }

        do {
            try activePlayer?.cancel()
            activePlayer = nil

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
            try player.start(atTime: CHHapticTimeImmediate)
            activePlayer = player
        } catch {
            // Haptic failure is non-fatal
        }
    }
}

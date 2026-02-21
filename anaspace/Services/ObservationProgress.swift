import Foundation

// MARK: - Observation Event

struct ObservationEvent: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

// MARK: - Observation Progress

@Observable @MainActor
final class ObservationProgress {
    // Phase & mode
    private(set) var phase: ObservationPhase = .idle
    private(set) var mode: ObservationMode = .tap

    // Per-service active state
    private(set) var isShazamActive = false
    private(set) var isSpeechActive = false
    private(set) var isSoundAnalysisActive = false
    private(set) var isClaudeProcessing = false

    // Timing
    private(set) var captureStartTime: Date?
    private(set) var elapsed: TimeInterval = 0

    // Live-updating signals
    private(set) var shazamResult: ShazamResult?
    private(set) var transcript: TranscriptResult?
    private(set) var audioScene: AudioScene = .unknown
    private(set) var location: LocationResult?

    // Result
    private(set) var latestResult: ClaudeResult?
    private(set) var isResultSuperseded = false
    private(set) var resultVersion: Int = 0

    // Play-by-play event log
    private(set) var events: [ObservationEvent] = []

    func logEvent(_ message: String) {
        let event = ObservationEvent(timestamp: .now, message: message)
        events.append(event)
        print("[Progress] \(message)")
    }

    func transitionTo(_ newPhase: ObservationPhase) {
        phase = newPhase
        logEvent("Phase → \(newPhase.rawValue)")
    }

    func setMode(_ newMode: ObservationMode) {
        mode = newMode
        logEvent("Mode → \(newMode.rawValue)")
    }

    func setShazamActive(_ active: Bool) {
        isShazamActive = active
        logEvent("Shazam: \(active ? "active" : "inactive")")
    }

    func setSpeechActive(_ active: Bool) {
        isSpeechActive = active
        logEvent("Speech: \(active ? "active" : "inactive")")
    }

    func setSoundAnalysisActive(_ active: Bool) {
        isSoundAnalysisActive = active
        logEvent("SoundAnalysis: \(active ? "active" : "inactive")")
    }

    func setClaudeProcessing(_ processing: Bool) {
        isClaudeProcessing = processing
        logEvent("Apple LLM: \(processing ? "processing" : "done")")
    }

    func startCaptureTiming() {
        captureStartTime = .now
        elapsed = 0
    }

    func updateElapsed() {
        guard let start = captureStartTime else { return }
        elapsed = Date.now.timeIntervalSince(start)
    }

    func setShazamResult(_ result: ShazamResult?) {
        shazamResult = result
        if let result {
            logEvent("Shazam match: \(result.title) by \(result.artist)")
        }
    }

    func setTranscript(_ result: TranscriptResult?) {
        let isNew = result?.text != transcript?.text
        transcript = result
        if let result, isNew {
            logEvent("Transcript: \"\(result.text)\" (final: \(result.isFinal), confidence: \(String(format: "%.2f", result.confidence)))")
        }
    }

    func setAudioScene(_ scene: AudioScene) {
        audioScene = scene
    }

    func setLocation(_ result: LocationResult?) {
        location = result
        if let result {
            logEvent("Location: \(result.city ?? "unknown")")
        }
    }

    func setLatestResult(_ result: ClaudeResult?, superseded: Bool = false) {
        latestResult = result
        isResultSuperseded = superseded
        resultVersion += 1
        if let result {
            logEvent("Apple LLM result: \(result.subject) (streaming: \(result.isStreaming))")
        }
    }

    func markResultSuperseded() {
        isResultSuperseded = true
        logEvent("Result superseded by new Apple LLM request")
    }

    func reset() {
        phase = .idle
        mode = .tap
        isShazamActive = false
        isSpeechActive = false
        isSoundAnalysisActive = false
        isClaudeProcessing = false
        captureStartTime = nil
        elapsed = 0
        shazamResult = nil
        transcript = nil
        audioScene = .unknown
        location = nil
        latestResult = nil
        isResultSuperseded = false
        resultVersion = 0
        events = []
    }
}

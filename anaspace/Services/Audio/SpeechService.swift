import AVFoundation
import Speech

// MARK: - Speech Service

@Observable
@MainActor
final class SpeechService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool
    private(set) var currentTranscript: TranscriptResult?
    private(set) var isTranscribing = false

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    weak var audioService: AudioService?

    // MARK: - Initialization

    init() {
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        self.recognizer = recognizer
        self.isAvailable = recognizer?.isAvailable ?? false
    }

    // MARK: - ObservationService Conformance

    func activate() async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ServiceError.speechRecognizerUnavailable
        }

        currentTranscript = nil
        isTranscribing = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let transcription = result.bestTranscription
                    let confidence: Double
                    if let lastSegment = transcription.segments.last {
                        confidence = Double(lastSegment.confidence)
                    } else {
                        confidence = 0.0
                    }

                    self.currentTranscript = TranscriptResult(
                        text: transcription.formattedString,
                        confidence: confidence,
                        isFinal: result.isFinal
                    )

                    if result.isFinal {
                        self.isTranscribing = false
                    }
                }

                if error != nil {
                    self.isTranscribing = false
                }
            }
        }

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

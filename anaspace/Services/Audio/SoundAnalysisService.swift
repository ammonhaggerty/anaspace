@preconcurrency import AVFoundation
import CoreMedia
@preconcurrency import SoundAnalysis

// MARK: - Sound Analysis Service

@Observable
@MainActor
final class SoundAnalysisService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = true
    private(set) var currentScene: AudioScene = .unknown

    private var analyzer: SNAudioStreamAnalyzer?
    private let observer = SoundAnalysisObserver()
    private let analysisQueue = DispatchQueue(label: "com.anaspace.soundanalysis")

    weak var audioService: AudioService?

    // MARK: - ObservationService Conformance

    func activate() async throws {
        guard let inputFormat = audioService?.inputFormat else {
            throw ServiceError.audioFormatUnavailable
        }

        currentScene = .unknown

        let streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)
        self.analyzer = streamAnalyzer

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 1000)
        request.overlapFactor = 0.5

        observer.onClassification = { [weak self] scene in
            Task { @MainActor in
                self?.currentScene = scene
            }
        }

        try streamAnalyzer.add(request, withObserver: observer)

        nonisolated(unsafe) let unsafeAnalyzer = streamAnalyzer
        audioService?.registerConsumer(id: "soundanalysis") { [weak self] buffer, time in
            guard let self else { return }
            self.analysisQueue.async {
                unsafeAnalyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
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

// MARK: - Sound Analysis Observer

private final class SoundAnalysisObserver: NSObject, SNResultsObserving {

    var onClassification: ((AudioScene) -> Void)?

    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let classificationResult = result as? SNClassificationResult,
              let topClassification = classificationResult.classifications.first else {
            return
        }

        let scene = mapLabelToScene(
            label: topClassification.identifier,
            confidence: topClassification.confidence
        )
        onClassification?(scene)
    }

    func request(_ request: any SNRequest, didFailWithError error: any Error) {}

    func requestDidComplete(_ request: any SNRequest) {}

    // MARK: - Label Mapping

    private func mapLabelToScene(label: String, confidence: Double) -> AudioScene {
        guard confidence >= 0.3 else {
            return .ambient
        }

        let lowercased = label.lowercased()

        if lowercased.contains("music") && lowercased.contains("speech") {
            return .musicAndSpeech
        } else if lowercased.contains("music") || lowercased.contains("singing") {
            return .music
        } else if lowercased.contains("speech") || lowercased.contains("conversation") {
            return .speech
        } else if lowercased.contains("silence") {
            return .silence
        }

        return .ambient
    }
}

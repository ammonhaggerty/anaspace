import AVFoundation

// MARK: - Audio Buffer Handler

typealias AudioBufferHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

// MARK: - Audio Service

@Observable
@MainActor
final class AudioService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = true
    private(set) var inputFormat: AVAudioFormat?
    private(set) var currentLevel: Float = 0

    private var engine: AVAudioEngine?
    private var consumers: [String: AudioBufferHandler] = [:]

    // MARK: - ObservationService Conformance

    func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw ServiceError.audioFormatUnavailable
        }

        self.inputFormat = format
        self.engine = engine

        // Register level meter consumer for VU meter
        registerConsumer(id: "levelMeter") { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sumSquares: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sumSquares += sample * sample
            }
            let rms = sqrtf(sumSquares / Float(frameCount))
            let dB = 20 * log10f(max(rms, 1e-10))
            let normalized = max(0, min(1, (dB + 50) / 50))

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentLevel = self.currentLevel * 0.7 + normalized * 0.3
            }
        }

        let capturedConsumers = consumers

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { buffer, time in
            for handler in capturedConsumers.values {
                handler(buffer, time)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func deactivate() {
        removeConsumer(id: "levelMeter")
        currentLevel = 0
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputFormat = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Consumer Registration

    func registerConsumer(id: String, handler: @escaping AudioBufferHandler) {
        consumers[id] = handler
    }

    func removeConsumer(id: String) {
        consumers.removeValue(forKey: id)
    }

    func removeAllConsumers() {
        consumers.removeAll()
    }

    /// Re-installs the tap with the current consumers dictionary.
    /// Call this if consumers are added or removed after `activate()`.
    func refreshTap() {
        guard let engine, let inputFormat else { return }

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)

        let capturedConsumers = consumers

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { buffer, time in
            for handler in capturedConsumers.values {
                handler(buffer, time)
            }
        }
    }
}

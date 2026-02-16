import AVFoundation
import Foundation

@Observable @MainActor
final class AudioPlayerService {

    // MARK: - State

    private(set) var state: PlayerState = .idle
    private(set) var currentTrack: TrackInfo?
    private(set) var queue: [TrackInfo] = []
    private(set) var currentLevel: Float = 0
    private(set) var peakLevel: Float = 0
    private(set) var tickerOffset: Int = 0

    // MARK: - Engine

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var displayTimer: Timer?
    private var tickerTimer: Timer?
    private var peakDecayTimer: Timer?
    private var fadeTimer: Timer?
    private var downloadTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var currentFile: AVAudioFile?

    // Display update target
    private weak var displayGrid: CharacterGrid?
    private var displayRow: Int = 0

    // MARK: - Public API

    func play() {
        guard state == .paused || (state == .idle && !queue.isEmpty) else { return }
        if state == .paused {
            playerNode?.play()
            state = .playing
            startDisplayUpdates()
        } else {
            playNext()
        }
    }

    func stop() {
        playerNode?.stop()
        state = .paused
        currentLevel = 0
        renderPlayerRow()
    }

    func skip() {
        playerNode?.stop()
        currentLevel = 0
        peakLevel = 0
        playNext()
    }

    func togglePlayStop() {
        switch state {
        case .playing: stop()
        case .paused: play()
        case .idle where !queue.isEmpty: play()
        default: break
        }
    }

    func loadQueue(_ tracks: [TrackInfo]) {
        queue = tracks
    }

    func loadFromStream(_ stream: AsyncStream<TrackInfo>, autoplay: Bool) {
        streamTask?.cancel()
        streamTask = Task {
            var first = true
            for await track in stream {
                guard !Task.isCancelled else { return }
                queue.append(track)
                if first {
                    first = false
                    if autoplay {
                        playNext()
                    } else {
                        // Render once to show idle-with-content state (ticker, controls)
                        renderPlayerRow()
                    }
                }
            }
        }
    }

    func beginFadeAndPrepareForCapture() {
        guard state == .playing else {
            stopEngine()
            return
        }
        state = .fading
        var volume: Float = 1.0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                volume -= 0.05 / 3.0  // ~3s fade
                if volume <= 0 {
                    self.fadeTimer?.invalidate()
                    self.fadeTimer = nil
                    self.stopEngine()
                    self.state = .idle
                    self.currentLevel = 0
                    self.peakLevel = 0
                    self.renderPlayerRow()
                } else {
                    self.playerNode?.volume = volume
                }
            }
        }
    }

    func stopEngine() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        currentFile = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Display Updates

    func setDisplayTarget(grid: CharacterGrid, row: Int) {
        displayGrid = grid
        displayRow = row
    }

    func startDisplayUpdates() {
        stopDisplayUpdates()

        // VU meter + render at ~12fps
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderPlayerRow()
            }
        }

        // Ticker scroll at ~4 chars/sec
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .playing else { return }
                self.tickerOffset += 1
            }
        }

        // Peak decay at 500ms/bar
        peakDecayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.peakLevel > self.currentLevel {
                    self.peakLevel = max(0, self.peakLevel - 1.0 / 6.0)
                }
            }
        }
    }

    func stopDisplayUpdates() {
        displayTimer?.invalidate()
        displayTimer = nil
        tickerTimer?.invalidate()
        tickerTimer = nil
        peakDecayTimer?.invalidate()
        peakDecayTimer = nil
    }

    // MARK: - Grid Rendering

    func renderPlayerRow() {
        guard let grid = displayGrid else { return }
        renderPlayerRow(into: grid, at: displayRow)
    }

    func renderPlayerRow(into grid: CharacterGrid, at row: Int) {
        guard row >= 0, row < grid.rowCount else { return }
        let cols = GridMetrics.columns  // 33

        // Clear the row first
        grid.clearRow(layer: .content, row: row)

        let hasContent = state != .idle || !queue.isEmpty || currentTrack != nil

        guard hasContent else {
            grid.render()
            return
        }

        // Cols 0-5: VU meter — 6 ═ bars
        let activeBars = Int((currentLevel * 6).rounded())
        let peakBar = min(5, Int((peakLevel * 6).rounded()))

        for col in 0..<6 {
            let isActive = col < activeBars
            let isPeak = col == peakBar && peakLevel > currentLevel && state == .playing

            if isPeak {
                grid.setCell(
                    layer: .content, row: row, col: col,
                    state: CellState(character: "\u{2502}", color: .bold, bold: true)
                )
            } else if isActive {
                let color: GridColor = col >= 5 ? .focus : .bold
                grid.setCell(
                    layer: .content, row: row, col: col,
                    state: CellState(character: "\u{2550}", color: color, bold: true)
                )
            } else {
                grid.setCell(
                    layer: .content, row: row, col: col,
                    state: CellState(character: "\u{2550}", color: .tint, bold: false)
                )
            }
        }

        // Col 6: peak hold position
        if peakLevel > currentLevel && state == .playing {
            // Already rendered as part of VU if within 0-5
        } else {
            grid.setCell(
                layer: .content, row: row, col: 6,
                state: CellState(character: " ", color: .clear, bold: false)
            )
        }

        // Cols 7-25: Ticker tape — 19 chars
        let tickerWidth = 19
        let tickerText = buildTickerText()
        if !tickerText.isEmpty {
            let chars = Array(tickerText)
            for i in 0..<tickerWidth {
                let charIndex = (tickerOffset + i) % chars.count
                let ch = chars[charIndex]
                grid.setCell(
                    layer: .content, row: row, col: 7 + i,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
            }
        }

        // Col 26: spacer
        grid.setCell(
            layer: .content, row: row, col: 26,
            state: CellState(character: " ", color: .clear, bold: false)
        )

        // Cols 27-28: Play/Stop
        let playStopChar: Character = state == .playing ? "\u{25A0}" : "\u{25B6}"
        grid.setCell(
            layer: .content, row: row, col: 28,
            state: CellState(character: playStopChar, color: .bold, bold: true)
        )

        // Cols 29-30: spacer
        // Cols 31-32: Skip ▸▸
        if cols > 31 {
            grid.setCell(
                layer: .content, row: row, col: 31,
                state: CellState(character: "\u{25B8}", color: .bold, bold: true)
            )
        }
        if cols > 32 {
            grid.setCell(
                layer: .content, row: row, col: 32,
                state: CellState(character: "\u{25B8}", color: .bold, bold: true)
            )
        }

        grid.render()
    }

    // MARK: - Private

    private func buildTickerText() -> String {
        let track: TrackInfo?
        if state == .playing || state == .paused || state == .fading {
            track = currentTrack
        } else if let next = queue.first {
            track = next
        } else {
            track = nil
        }
        guard let track else { return "" }
        let text = "\(track.artist) | \(track.title) | \(track.year)".uppercased()
        // Pad with spaces for smooth scroll wrap
        return text + "   "
    }

    private func playNext() {
        guard !queue.isEmpty else {
            state = .idle
            currentTrack = nil
            currentLevel = 0
            peakLevel = 0
            stopDisplayUpdates()
            renderPlayerRow()
            return
        }

        let track = queue.removeFirst()
        currentTrack = track
        state = .loading
        tickerOffset = 0

        downloadTask?.cancel()
        downloadTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: track.previewURL)
                guard !Task.isCancelled else { return }

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".m4a")
                try data.write(to: tempURL)

                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }

                await startPlayback(fileURL: tempURL)
            } catch {
                // Skip to next track on download failure
                playNext()
            }
        }
    }

    private func startPlayback(fileURL: URL) async {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)

            let file = try AVAudioFile(forReading: fileURL)
            currentFile = file

            let engine = AVAudioEngine()
            let playerNode = AVAudioPlayerNode()
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)

            // Install metering tap on main mixer
            let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: mixerFormat) { [weak self] buffer, _ in
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
                    let smoothed = self.currentLevel * 0.7 + normalized * 0.3
                    self.currentLevel = smoothed
                    if smoothed > self.peakLevel {
                        self.peakLevel = smoothed
                    }
                }
            }

            engine.prepare()
            try engine.start()

            self.engine = engine
            self.playerNode = playerNode

            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: fileURL)
                    guard self.state == .playing else { return }
                    self.currentLevel = 0
                    self.peakLevel = 0
                    self.playNext()
                }
            }

            playerNode.play()
            state = .playing
            startDisplayUpdates()
        } catch {
            // Clean up and skip
            try? FileManager.default.removeItem(at: fileURL)
            playNext()
        }
    }
}

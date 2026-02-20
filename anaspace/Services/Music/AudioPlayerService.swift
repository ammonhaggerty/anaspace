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
    private(set) var trackDuration: Int = 30
    private(set) var secondsRemaining: Int = 30

    /// Session-level pause flag. Set when user manually pauses, cleared on play or new observation.
    private var userPaused: Bool = false

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
    private var playbackStartDate: Date?
    private var pausedElapsed: TimeInterval = 0

    // Display update target
    private weak var displayGrid: CharacterGrid?
    private var displayRow: Int = 0

    // MARK: - Volume Diagnostics

    private func logVolumeState(_ context: String) {
        let session = AVAudioSession.sharedInstance()
        let vol = playerNode?.volume ?? -1
        let category = session.category.rawValue
        let mode = session.mode.rawValue
        let outputVol = session.outputVolume
        let isOtherPlaying = session.isOtherAudioPlaying
        let engineRunning = engine?.isRunning ?? false
        let nodeIsPlaying = playerNode?.isPlaying ?? false
        print("[AudioDiag] \(context) | vol=\(vol) sysVol=\(outputVol) cat=\(category) mode=\(mode) engineRun=\(engineRunning) nodePlay=\(nodeIsPlaying) otherAudio=\(isOtherPlaying) state=\(state)")
    }

    private func checkVolumeAnomaly(_ context: String) {
        let vol = playerNode?.volume ?? -1
        let session = AVAudioSession.sharedInstance()
        // Flag if: playing but volume near zero, or session category isn't playback
        if state == .playing && (vol < 0.05 || session.category != .playback) {
            logVolumeState("ANOMALY \(context)")
        }
    }

    // MARK: - Public API

    func play() {
        guard state == .paused || (state == .idle && !queue.isEmpty) else { return }
        userPaused = false
        if state == .paused {
            playerNode?.volume = 1.0
            playerNode?.play()
            playbackStartDate = Date.now
            state = .playing
            startDisplayUpdates()
        } else {
            playNext()
        }
    }

    func stop() {
        userPaused = true
        // Save elapsed time for resume
        if let start = playbackStartDate {
            pausedElapsed += Date.now.timeIntervalSince(start)
        }
        playbackStartDate = nil
        playerNode?.pause()
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

    /// Reset session pause state. Call when a new observation starts.
    func resetSessionPause() {
        userPaused = false
    }

    func loadFromStream(_ stream: AsyncStream<TrackInfo>, autoplay: Bool) {
        streamTask?.cancel()
        downloadTask?.cancel()

        // Stop current playback and clear stale queue
        playerNode?.stop()
        engine?.mainMixerNode.removeTap(onBus: 0)
        stopEngine()
        queue.removeAll()
        currentTrack = nil
        currentLevel = 0
        peakLevel = 0
        playbackStartDate = nil
        pausedElapsed = 0
        state = .idle
        stopDisplayUpdates()

        streamTask = Task {
            var first = true
            for await track in stream {
                guard !Task.isCancelled else { return }
                queue.append(track)
                if first {
                    first = false
                    if autoplay && !self.userPaused {
                        playNext()
                    } else {
                        // Render once to show idle-with-content state (ticker, controls)
                        renderPlayerRow()
                    }
                }
            }
        }
    }

    /// Transition to a new stream with a 2s fade-out of the current playback.
    func transitionToStream(_ stream: AsyncStream<TrackInfo>, autoplay: Bool) {
        guard state == .playing || state == .paused else {
            loadFromStream(stream, autoplay: autoplay)
            return
        }

        state = .fading
        fadeTimer?.invalidate()
        var volume = playerNode?.volume ?? 1.0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                volume -= 0.05 / 2.0  // ~2s fade
                if volume <= 0 {
                    self.logVolumeState("fadeComplete-loadNewStream")
                    self.fadeTimer?.invalidate()
                    self.fadeTimer = nil
                    self.loadFromStream(stream, autoplay: autoplay)
                } else {
                    self.playerNode?.volume = volume
                }
            }
        }
    }

    /// Fade out current playback without loading new content.
    /// Used when a context change grid appears — old music fades while new playlist loads.
    func fadeOut(duration: TimeInterval = 1.5) {
        guard state == .playing else { return }

        state = .fading
        fadeTimer?.invalidate()
        var volume = playerNode?.volume ?? 1.0
        let stepSize = Float(0.05 / duration)

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .fading else { return }
                volume -= stepSize
                if volume <= 0 {
                    self.fadeTimer?.invalidate()
                    self.fadeTimer = nil
                    self.stopEngine()
                    self.state = .idle
                    self.currentLevel = 0
                    self.peakLevel = 0
                    self.stopDisplayUpdates()
                    self.renderPlayerRow()
                } else {
                    self.playerNode?.volume = volume
                }
            }
        }
    }

    func beginFadeAndPrepareForCapture() {
        logVolumeState("beginFadeAndPrepareForCapture")
        stopEngine()
        state = .idle
        currentLevel = 0
        peakLevel = 0
        renderPlayerRow()
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

        // Countdown + render at ~12fps
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateCountdown()
                self.renderPlayerRow()
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

        // Remove structure background when player is active
        grid.clearRow(layer: .structure, row: row)

        // Cols 0-5: Countdown ":27/30"
        let countdownText = String(format: ":%02d/%d", secondsRemaining, trackDuration)
        let isWarning = secondsRemaining <= 5 && state == .playing
        for (i, ch) in countdownText.enumerated() {
            guard i < 6 else { break }
            let isCountdownDigit = i >= 1 && i <= 2
            let color: GridColor = (isWarning && isCountdownDigit) ? .focus : .bold
            grid.setCell(
                layer: .content, row: row, col: i,
                state: CellState(character: ch, color: color, bold: true, small: true)
            )
        }

        // Col 6: spacer

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
                    state: CellState(character: ch, color: .bold, bold: true, small: true)
                )
            }
        }

        // Col 26: spacer

        // Cols 27-28: Play/Stop
        let playStopChar: Character = state == .playing ? "\u{25A0}" : "\u{E0B0}"
        grid.setCell(
            layer: .content, row: row, col: 28,
            state: CellState(character: playStopChar, color: .bold, bold: true, small: true)
        )

        // Cols 29-30: spacer
        // Cols 31-32: Skip ▸▸
        if cols > 31 {
            grid.setCell(
                layer: .content, row: row, col: 31,
                state: CellState(character: "\u{E0B1}", color: .bold, bold: true, small: true)
            )
        }
        if cols > 32 {
            grid.setCell(
                layer: .content, row: row, col: 32,
                state: CellState(character: "\u{E0B1}", color: .bold, bold: true, small: true)
            )
        }

        grid.render()
    }

    // MARK: - Countdown

    private func updateCountdown() {
        guard state == .playing, let start = playbackStartDate else { return }
        let elapsed = pausedElapsed + Date.now.timeIntervalSince(start)
        let exactRemaining = Double(trackDuration) - elapsed
        secondsRemaining = max(0, Int(exactRemaining))

        // Volume envelope: 1s fade-in, 2s fade-out
        if elapsed < 1.0 {
            playerNode?.volume = Float(elapsed)
        } else if exactRemaining <= 2.0 && exactRemaining > 0 {
            playerNode?.volume = Float(exactRemaining / 2.0)
        } else {
            checkVolumeAnomaly("envelope-steady")
            playerNode?.volume = 1.0
        }
    }

    // MARK: - VU Meter (reserved for future audio player)

    /// Render a 6-bar VU meter with peak hold. Not currently used — kept for future full player.
    func renderVUMeter(into grid: CharacterGrid, row: Int) {
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

        // Col 6: peak hold
        if peakLevel > currentLevel && state == .playing {
            // Peak indicator rendered within bars 0-5 above
        } else {
            grid.setCell(
                layer: .content, row: row, col: 6,
                state: CellState(character: " ", color: .clear, bold: false)
            )
        }
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
            playbackStartDate = nil
            pausedElapsed = 0
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

            // Compute track duration from file
            let fileDuration = Double(file.length) / file.processingFormat.sampleRate
            trackDuration = max(1, Int(fileDuration.rounded()))
            secondsRemaining = trackDuration
            pausedElapsed = 0

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

            playerNode.volume = 0
            playerNode.play()
            playbackStartDate = Date.now
            state = .playing
            logVolumeState("startPlayback")
            startDisplayUpdates()
        } catch {
            // Clean up and skip
            try? FileManager.default.removeItem(at: fileURL)
            playNext()
        }
    }
}

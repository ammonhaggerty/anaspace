import UIKit

@MainActor
final class CaptureRenderer: NSObject {

    enum Mode {
        case observing
        case listening
        case evaluating
    }

    // MARK: - Signal Carousel

    struct SignalItem {
        let label: String   // e.g. "LOCATION"
        let value: String   // e.g. "OAKLAND, CA"
        var text: String { "\(label): \(value)" }
    }

    private enum SignalPhase {
        case building    // 300ms — characters appear L→R
        case holding     // 1000ms — full text visible
        case unbuilding  // 300ms — characters disappear L→R
        case gap         // 100ms pause before next
    }

    // MARK: - Properties

    private(set) var mode: Mode = .observing

    private weak var grid: CharacterGrid?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    private weak var progress: ObservationProgress?
    private weak var audioService: AudioService?

    private var lastTranscriptText: String?
    private var cols: Int = 0

    // Shazam indicator state
    private var indicatorToggle = false
    private var lastIndicatorToggle: CFTimeInterval = 0

    // Signal carousel state
    private var signals: [SignalItem] = []
    private var currentSignalIndex: Int = 0
    private var signalPhase: SignalPhase = .building
    private var signalPhaseStart: CFTimeInterval = 0

    // Callback for structural changes when entering evaluating
    var onTransitionToEvaluating: (() -> Void)?

    // MARK: - Public API

    func start(on grid: CharacterGrid, mode: Mode, progress: ObservationProgress, audioService: AudioService) {
        stop()

        self.grid = grid
        self.mode = mode
        self.progress = progress
        self.audioService = audioService
        self.cols = GridMetrics.columns
        self.lastTranscriptText = nil
        self.indicatorToggle = false
        self.lastIndicatorToggle = 0
        self.signals = []
        self.currentSignalIndex = 0
        self.signalPhase = .building
        self.signalPhaseStart = 0

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 15, preferred: 15)
        startTime = 0
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        grid = nil
        progress = nil
        audioService = nil
    }

    func upgradeToListening() {
        mode = .listening
    }

    func transitionToEvaluating(signals: [SignalItem]) {
        mode = .evaluating
        self.signals = signals
        self.currentSignalIndex = 0
        self.signalPhase = .building
        self.signalPhaseStart = 0
    }

    // MARK: - Frame Loop

    @objc private func tick(_ link: CADisplayLink) {
        guard let grid, let progress else {
            stop()
            return
        }

        if startTime == 0 { startTime = link.timestamp }
        let elapsed = link.timestamp - startTime

        // Auto-transition to evaluating when phase becomes .processing
        if mode != .evaluating && progress.phase == .processing {
            collectSignalsAndTransition(progress: progress)
        }

        switch mode {
        case .observing, .listening:
            renderCaptureHeader(grid: grid, progress: progress, elapsed: elapsed)
            if mode == .listening {
                renderTranscript(grid: grid, progress: progress)
            }
        case .evaluating:
            renderEvaluatingHeader(grid: grid, progress: progress)
            renderSignalCarousel(grid: grid, elapsed: elapsed)
        }

        grid.render()
    }

    // MARK: - Auto-transition

    private func collectSignalsAndTransition(progress: ObservationProgress) {
        var items: [SignalItem] = []

        // Location (always available)
        if let loc = progress.location {
            let label = LocationService.displayLabel(for: loc)
            items.append(SignalItem(label: "LOCATION", value: label))
        } else {
            items.append(SignalItem(label: "LOCATION", value: "LOCATING..."))
        }

        // Year (always current year)
        let year = Calendar.current.component(.year, from: Date())
        items.append(SignalItem(label: "YEAR", value: "\(year)"))

        // Shazam results
        if let shazam = progress.shazamResult {
            items.append(SignalItem(label: "ARTIST", value: shazam.artist.uppercased()))
            items.append(SignalItem(label: "SONG", value: shazam.title.uppercased()))
            if let genre = shazam.genres.first {
                items.append(SignalItem(label: "GENRE", value: genre.uppercased()))
            }
        }

        transitionToEvaluating(signals: items)
        onTransitionToEvaluating?()
    }

    // MARK: - Capture Header (Observing / Listening)

    private func renderCaptureHeader(grid: CharacterGrid, progress: ObservationProgress, elapsed: CFTimeInterval) {
        var row0 = [CellState](repeating: .empty, count: cols)

        // VU meter: cols 0-4 (5 levels: ◦◯◎●█)
        if let audioService {
            let level = audioService.currentLevel
            let vuGlyphs: [(Character, Float)] = [
                ("\u{25E6}", 0.01),  // ◦ — any sound
                ("\u{25CB}", 0.04),  // ○ — quiet
                ("\u{25CE}", 0.10),  // ◎ — moderate
                ("\u{25CF}", 0.22),  // ● — loud
                ("\u{2588}", 0.35),  // █ — clipping
            ]
            for (i, (glyph, threshold)) in vuGlyphs.enumerated() {
                if level >= threshold {
                    let color: GridColor = i >= 4 ? .focus : .bold
                    row0[i] = CellState(character: glyph, color: color, bold: false)
                } else {
                    row0[i] = CellState(character: "\u{25E6}", color: .tint, bold: false)
                }
            }
        }

        // Mode label: centered
        let label = mode == .observing ? "OBSERVING" : "LISTENING"
        let labelStart = (cols - label.count) / 2
        for (i, ch) in label.enumerated() {
            let col = labelStart + i
            guard col < cols else { break }
            row0[col] = CellState(character: ch, color: .bold, bold: false)
        }

        // Right side: countdown or Shazam indicator
        switch mode {
        case .observing:
            let remaining = max(0, 10.0 - progress.elapsed)
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            let timeStr = "\(mins):\(String(format: "%02d", secs))"
            let timeStart = cols - timeStr.count
            for (i, ch) in timeStr.enumerated() {
                let col = timeStart + i
                guard col >= 0, col < cols else { continue }
                row0[col] = CellState(character: ch, color: .bold, bold: false)
            }

        case .listening:
            renderShazamIndicator(into: &row0, progress: progress, elapsed: elapsed)

        case .evaluating:
            break
        }

        grid.setRow(layer: .content, row: 0, states: row0)
    }

    // MARK: - Evaluating Header

    private func renderEvaluatingHeader(grid: CharacterGrid, progress: ObservationProgress) {
        var row0 = [CellState](repeating: .empty, count: cols)

        // "EVALUATING" centered
        let label = "EVALUATING"
        let labelStart = (cols - label.count) / 2
        for (i, ch) in label.enumerated() {
            let col = labelStart + i
            guard col < cols else { break }
            row0[col] = CellState(character: ch, color: .bold, bold: false)
        }

        // ID status: right-aligned
        let hasMatch = progress.shazamResult != nil
        let indicator = hasMatch ? "ID\u{2713}" : "ID\u{00D7}"
        let indStart = cols - indicator.count
        for (i, ch) in indicator.enumerated() {
            let col = indStart + i
            guard col >= 0, col < cols else { continue }
            row0[col] = CellState(character: ch, color: hasMatch ? .bold : .bold, bold: false)
        }

        grid.setRow(layer: .content, row: 0, states: row0)

        // Clear rows 1-2 (signal carousel uses row 2)
        grid.clearRow(layer: .content, row: 1)
        grid.clearRow(layer: .content, row: 2)
    }

    // MARK: - Signal Carousel

    private func renderSignalCarousel(grid: CharacterGrid, elapsed: CFTimeInterval) {
        guard !signals.isEmpty else { return }

        // Initialize phase start on first call
        if signalPhaseStart == 0 { signalPhaseStart = elapsed }

        let phaseElapsed = elapsed - signalPhaseStart
        let signal = signals[currentSignalIndex % signals.count]
        let fullText = signal.text
        let textLen = fullText.count

        switch signalPhase {
        case .building:
            let progress = min(1.0, phaseElapsed / 0.3)
            let charsToShow = Int(Double(textLen) * progress)
            renderSignalText(fullText, charsVisible: charsToShow, grid: grid)
            if progress >= 1.0 {
                signalPhase = .holding
                signalPhaseStart = elapsed
            }

        case .holding:
            renderSignalText(fullText, charsVisible: textLen, grid: grid)
            if phaseElapsed >= 1.0 {
                signalPhase = .unbuilding
                signalPhaseStart = elapsed
            }

        case .unbuilding:
            let progress = min(1.0, phaseElapsed / 0.3)
            let charsToShow = textLen - Int(Double(textLen) * progress)
            renderSignalText(fullText, charsVisible: max(0, charsToShow), grid: grid)
            if progress >= 1.0 {
                signalPhase = .gap
                signalPhaseStart = elapsed
            }

        case .gap:
            grid.clearRow(layer: .content, row: 2)
            if phaseElapsed >= 0.1 {
                currentSignalIndex = (currentSignalIndex + 1) % signals.count
                signalPhase = .building
                signalPhaseStart = elapsed
            }
        }
    }

    private func renderSignalText(_ text: String, charsVisible: Int, grid: CharacterGrid) {
        var row2 = [CellState](repeating: .empty, count: cols)
        let chars = Array(text)
        let start = max(0, (cols - chars.count) / 2)

        for i in 0..<min(charsVisible, chars.count) {
            let col = start + i
            guard col < cols else { break }
            row2[col] = CellState(character: chars[i], color: .bold, bold: false)
        }

        grid.setRow(layer: .content, row: 2, states: row2)
    }

    // MARK: - Shazam Indicator

    private func renderShazamIndicator(into row: inout [CellState], progress: ObservationProgress, elapsed: CFTimeInterval) {
        let indicator: String
        if progress.shazamResult != nil {
            indicator = "ID\u{2713}"
        } else {
            if elapsed - lastIndicatorToggle >= 0.25 {
                indicatorToggle.toggle()
                lastIndicatorToggle = elapsed
            }
            indicator = indicatorToggle ? "ID\u{25C9}" : "ID\u{25CB}"
        }
        let indStart = cols - indicator.count
        for (i, ch) in indicator.enumerated() {
            let col = indStart + i
            guard col >= 0, col < cols else { continue }
            let color: GridColor = progress.shazamResult != nil ? .focus : .bold
            row[col] = CellState(character: ch, color: color, bold: false)
        }
    }

    // MARK: - Transcript (Row 3+)

    private func renderTranscript(grid: CharacterGrid, progress: ObservationProgress) {
        guard let text = progress.transcript?.text, !text.isEmpty else { return }
        let upper = text.uppercased()
        guard upper != lastTranscriptText else { return }
        lastTranscriptText = upper

        // 1-cell padding: rows 3..<maxRow-1, cols 1..<cols-1
        let padCol = 1
        let maxCol = cols - 1
        let usableCols = maxCol - padCol
        let startRow = 3
        let maxRow = grid.rowCount - 1
        for row in startRow..<grid.rowCount {
            grid.clearRow(layer: .content, row: row)
        }

        let words = upper.split(separator: " ")
        var row = startRow
        var col = padCol

        for word in words {
            let wordLen = word.count
            if col - padCol + wordLen > usableCols && col > padCol {
                row += 1
                col = padCol
            }
            guard row < maxRow else { break }

            for ch in word {
                if col >= maxCol {
                    row += 1
                    col = padCol
                }
                guard row < maxRow else { break }
                grid.setCell(
                    layer: .content, row: row, col: col,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
                col += 1
            }
            col += 1
        }
    }
}

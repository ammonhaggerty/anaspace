import UIKit

// MARK: - Configuration

extension IdlePulseAnimation {

    struct Config {
        var initialDelay: Float = 6.0     // seconds before first pulse
        var pulseDuration: Float = 6.0    // seconds for inner edge to clear grid
        var pauseDuration: Float = 3.0    // seconds of stillness between pulses
        var skipRows: Set<Int> = []       // rows to leave untouched
    }

    // Symmetric gradient from outer edge to center and back out.
    static let gradient: [Character] = [
        "\u{233B}",  // ⌻  outer edge
        "\u{233E}",  // ⌾
        "\u{2219}",  // ∙  center
        "\u{233E}",  // ⌾
        "\u{233B}",  // ⌻  inner edge
    ]

    /// Total width of the ring: 5 gradient zones (1.0 each).
    static let ringWidth: Float = 5.0
}

// MARK: - IdlePulseAnimation

@MainActor
final class IdlePulseAnimation: NSObject, GridAnimation {

    var config = Config()
    var isRunning: Bool { displayLink != nil }

    private weak var grid: CharacterGrid?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?
    private var isPaused = false

    // Precomputed
    private var distances: [Float] = []
    private var cols: Int = 0
    private var rows: Int = 0
    private var maxDistance: Float = 0
    private var colScale: Float = 1.0

    // MARK: - Public

    func run(on grid: CharacterGrid, completion: @escaping () -> Void) {
        cancel()

        self.grid = grid
        self.completion = completion
        self.cols = GridMetrics.columns
        self.rows = grid.rowCount
        self.isPaused = false

        precompute()

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        startTime = 0
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        if let grid {
            restoreBase(grid)
        }
        grid = nil
        completion = nil
    }

    // MARK: - Precompute

    private func precompute() {
        guard let grid else { return }
        let totalCells = rows * cols

        // Aspect ratio correction for circular rings
        if let metrics = grid.metrics {
            let gridWidth = grid.bounds.width - 2 * GridMetrics.sideMargin
            let cellWidth = Float(gridWidth / CGFloat(cols))
            let cellHeight = Float(metrics.lineHeight)
            colScale = cellWidth / cellHeight
        }

        let centerCol: Float = Float(cols) / 2.0
        let centerRow: Float = Float(rows) / 2.0

        distances = [Float](repeating: 0, count: totalCells)
        maxDistance = 0

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                let dx = (Float(col) - centerCol) * colScale
                let dy = Float(row) - centerRow
                let dist = sqrtf(dx * dx + dy * dy)
                distances[idx] = dist
                if dist > maxDistance { maxDistance = dist }
            }
        }
    }

    // MARK: - Frame Loop

    @objc private func tick(_ link: CADisplayLink) {
        guard let grid else { cancel(); return }

        // Re-precompute if grid resized
        if grid.rowCount != rows {
            rows = grid.rowCount
            precompute()
        }

        if startTime == 0 { startTime = link.timestamp }
        let elapsed = Float(link.timestamp - startTime)

        // Circle indicator pulse: on 1000ms, off 200ms (runs immediately)
        pulseCircle(grid: grid, elapsed: elapsed)

        // Initial delay for ring animation — grid already shows base ░ from renderStructure
        guard elapsed >= config.initialDelay else {
            grid.render()
            return
        }

        let cycleDuration = config.pulseDuration + config.pauseDuration
        let cycleTime = (elapsed - config.initialDelay).truncatingRemainder(dividingBy: cycleDuration)

        // Pause phase — restore base once, circle keeps pulsing
        if cycleTime >= config.pulseDuration {
            if !isPaused {
                isPaused = true
                restoreBase(grid)
            }
            grid.render()
            return
        }
        isPaused = false

        // Pulse phase: wavefront = outer edge of ring, moves from 0 to maxDistance + ringWidth.
        // At pulseDuration the inner edge (wavefront - ringWidth) equals maxDistance.
        let progress = cycleTime / config.pulseDuration
        let rw = Self.ringWidth
        let wavefront = progress * (maxDistance + rw)
        let innerEdge = max(0, wavefront - rw)
        let gradient = Self.gradient
        let baseState = CellState(character: "\u{2591}", color: .tint, bold: false)

        for row in 0..<rows {
            if config.skipRows.contains(row) { continue }

            var states = [CellState](repeating: baseState, count: cols)
            for col in 0..<cols {
                let idx = row * cols + col
                let dist = distances[idx]
                guard dist >= innerEdge && dist <= wavefront else { continue }

                // ringPos: 0 at outer edge → ringWidth at inner edge
                let ringPos = wavefront - dist
                let zone = min(Int(ringPos), gradient.count - 1)
                states[col] = CellState(character: gradient[zone], color: .tint, bold: false)
            }
            grid.setRow(layer: .structure, row: row, states: states)
        }

        grid.render()
    }

    // MARK: - Circle Pulse

    private func pulseCircle(grid: CharacterGrid, elapsed: Float) {
        let circleRow = rows / 3 - 4 - 1
        let circleCol = cols / 2
        guard circleRow >= 0 && circleRow < rows else { return }

        // 1000ms on, 200ms off
        let cyclePeriod: Float = 1.2
        let onDuration: Float = 1.0
        let phase = elapsed.truncatingRemainder(dividingBy: cyclePeriod)
        let isOn = phase < onDuration

        let state = isOn
            ? CellState(character: "\u{25CF}", color: .focus, bold: false)
            : CellState.empty
        grid.setCell(layer: .content, row: circleRow, col: circleCol, state: state)
    }

    // MARK: - Helpers

    private func restoreBase(_ grid: CharacterGrid) {
        let fillState = CellState(character: "\u{2591}", color: .tint, bold: false)
        for row in 0..<grid.rowCount {
            if config.skipRows.contains(row) { continue }
            let states = [CellState](repeating: fillState, count: GridMetrics.columns)
            grid.setRow(layer: .structure, row: row, states: states)
        }
        grid.render()
    }
}

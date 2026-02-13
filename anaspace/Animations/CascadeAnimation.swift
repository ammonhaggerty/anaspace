import UIKit

@MainActor
final class CascadeAnimation: NSObject, GridAnimation {

    private(set) var isRunning = false

    private weak var grid: CharacterGrid?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?

    private var rowCount: Int = 0
    private var cols: Int = 0

    // Timing
    private let staggerInterval: Double = 0.015  // 15ms between rows
    private let holdDuration: Double = 0.05       // brief hold before clearing
    private let clearStaggerInterval: Double = 0.0075  // 7.5ms between clear rows

    // State tracking
    private var lastFilledRow: Int = -1
    private var lastClearedRow: Int = -1
    private var fillComplete = false
    private var fillCompleteTime: Double = 0

    // Medium-density glyphs for the transition sweep
    private static let transitionGlyphs: [Character] = Array("░▒▓█▐▌│─┼┤├┴┬╳╱╲◆◇○●")

    // Pre-generated glyph rows
    private var glyphRows: [[CellState]] = []

    func run(on grid: CharacterGrid, completion: @escaping () -> Void) {
        cancel()

        self.grid = grid
        self.completion = completion
        self.rowCount = grid.rowCount
        self.cols = GridMetrics.columns
        self.isRunning = true
        self.lastFilledRow = -1
        self.lastClearedRow = -1
        self.fillComplete = false
        self.fillCompleteTime = 0

        // Pre-generate all glyph rows
        glyphRows = (0..<rowCount).map { _ in
            (0..<self.cols).map { _ -> CellState in
                let glyph = Self.transitionGlyphs.randomElement()!
                return CellState(character: glyph, color: .tint, bold: false)
            }
        }

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        startTime = 0
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        if let grid {
            grid.clearLayer(.transition)
            grid.render()
        }
        grid = nil
        completion = nil
        glyphRows = []
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let grid else { cancel(); return }

        if startTime == 0 { startTime = link.timestamp }
        let elapsed = link.timestamp - startTime

        if !fillComplete {
            // Fill phase: advance rows based on elapsed time
            let targetRow = min(rowCount - 1, Int(elapsed / staggerInterval))

            for row in (lastFilledRow + 1)...targetRow {
                grid.setRow(layer: .transition, row: row, states: glyphRows[row])
            }

            if targetRow > lastFilledRow {
                lastFilledRow = targetRow
                grid.render()
            }

            if lastFilledRow >= rowCount - 1 {
                fillComplete = true
                fillCompleteTime = elapsed
            }
        } else {
            // Clear phase: after hold, clear rows top-to-bottom
            let clearElapsed = elapsed - fillCompleteTime - holdDuration
            guard clearElapsed >= 0 else { return }

            let targetClearRow = min(rowCount - 1, Int(clearElapsed / clearStaggerInterval))

            for row in (lastClearedRow + 1)...targetClearRow {
                grid.clearRow(layer: .transition, row: row)
            }

            if targetClearRow > lastClearedRow {
                lastClearedRow = targetClearRow
                grid.render()
            }

            if lastClearedRow >= rowCount - 1 {
                // Animation complete
                displayLink?.invalidate()
                displayLink = nil
                isRunning = false
                self.grid = nil
                glyphRows = []
                let cb = completion
                completion = nil
                cb?()
            }
        }
    }
}

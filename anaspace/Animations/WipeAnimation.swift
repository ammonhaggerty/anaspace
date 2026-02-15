import UIKit

@MainActor
final class WipeAnimation: NSObject, GridAnimation {

    var isRunning: Bool { displayLink != nil }
    var onRowCovered: ((Int) -> Void)?

    private weak var grid: CharacterGrid?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?

    private var totalCells: Int = 0
    private var cols: Int = 0
    private var rows: Int = 0
    private var lastProcessed: Int = -1
    private var isWipingOut: Bool = true

    private static let duration: Double = 0.6

    // MARK: - Public

    func run(on grid: CharacterGrid, completion: @escaping () -> Void) {
        wipeOut(on: grid, completion: completion)
    }

    func wipeOut(on grid: CharacterGrid, completion: @escaping () -> Void) {
        cancel()
        isWipingOut = true
        startAnimation(on: grid, completion: completion)
    }

    func wipeIn(on grid: CharacterGrid, completion: @escaping () -> Void) {
        cancel()
        isWipingOut = false
        startAnimation(on: grid, completion: completion)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        if let grid {
            grid.clearLayer(.transition)
            grid.render()
        }
        grid = nil
        completion = nil
    }

    // MARK: - Private

    private func startAnimation(on grid: CharacterGrid, completion: @escaping () -> Void) {
        self.grid = grid
        self.completion = completion
        self.cols = GridMetrics.columns
        self.rows = grid.rowCount
        self.totalCells = rows * cols
        self.lastProcessed = -1

        if !isWipingOut {
            // For wipe-in, start fully covered
            let fillState = CellState(character: "\u{2591}", color: .tint, bold: false)
            for row in 0..<rows {
                let states = [CellState](repeating: fillState, count: cols)
                grid.setRow(layer: .transition, row: row, states: states)
            }
            grid.render()
        }

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        startTime = 0
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let grid else { cancel(); return }

        if startTime == 0 { startTime = link.timestamp }
        let elapsed = link.timestamp - startTime

        let progress = min(1.0, elapsed / Self.duration)
        let targetCell = min(totalCells - 1, Int(progress * Double(totalCells)))

        guard targetCell > lastProcessed else {
            if progress >= 1.0 { finish() }
            return
        }

        let fillState = CellState(character: "\u{2591}", color: .tint, bold: false)
        var lastRowTouched = -1

        for cellIndex in (lastProcessed + 1)...targetCell {
            let row = cellIndex / cols
            let col = cellIndex % cols

            if isWipingOut {
                grid.setCell(layer: .transition, row: row, col: col, state: fillState)
            } else {
                grid.setCell(layer: .transition, row: row, col: col, state: .empty)
            }

            // Detect when last cell in a row is covered/revealed
            if col == cols - 1 {
                lastRowTouched = row
            }
        }

        lastProcessed = targetCell
        grid.render()

        // Fire row callback for completed rows
        if let onRowCovered, lastRowTouched >= 0 {
            onRowCovered(lastRowTouched)
        }

        if progress >= 1.0 {
            finish()
        }
    }

    private func finish() {
        displayLink?.invalidate()
        displayLink = nil
        self.grid = nil
        let cb = completion
        completion = nil
        cb?()
    }
}

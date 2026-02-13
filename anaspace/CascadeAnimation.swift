import Foundation

final class CascadeAnimation {

    private var workItem: DispatchWorkItem?
    private var isRunning = false

    // Medium-density glyphs for the transition sweep
    private static let transitionGlyphs: [Character] = Array("░▒▓█▐▌│─┼┤├┴┬╳╱╲◆◇○●")

    func run(on grid: CharacterGrid, completion: (() -> Void)? = nil) {
        cancel()

        let rowCount = grid.rowCount
        let cols = GridMetrics.columns
        let staggerMs = 15 // ms between rows
        isRunning = true

        let item = DispatchWorkItem { [weak self] in
            for row in 0..<rowCount {
                guard self?.isRunning == true else { return }

                // Fill transition layer row with random glyphs
                let states = (0..<cols).map { _ -> CellState in
                    let glyph = Self.transitionGlyphs.randomElement()!
                    return CellState(character: glyph, color: .structure, bold: false)
                }

                DispatchQueue.main.async {
                    grid.setRow(layer: .transition, row: row, states: states)
                    grid.render()
                }

                if row < rowCount - 1 {
                    Thread.sleep(forTimeInterval: Double(staggerMs) / 1000.0)
                }
            }

            // Brief hold, then clear transition layer top-to-bottom
            Thread.sleep(forTimeInterval: 0.05)

            for row in 0..<rowCount {
                guard self?.isRunning == true else { return }

                DispatchQueue.main.async {
                    grid.clearRow(layer: .transition, row: row)
                    grid.render()
                }

                if row < rowCount - 1 {
                    Thread.sleep(forTimeInterval: Double(staggerMs / 2) / 1000.0)
                }
            }

            DispatchQueue.main.async {
                self?.isRunning = false
                completion?()
            }
        }

        workItem = item
        DispatchQueue.global(qos: .userInteractive).async(execute: item)
    }

    func cancel() {
        isRunning = false
        workItem?.cancel()
        workItem = nil
    }
}

import Foundation

@MainActor
final class HistoryPageRenderer: PageRenderer {
    let page: Page = .history
    let hiddenStructureRows: Set<Int> = []

    func renderStructure(into grid: CharacterGrid) {
        let cols = GridMetrics.columns
        for row in 0..<grid.rowCount {
            for col in 0..<cols {
                grid.setCell(
                    layer: .structure, row: row, col: col,
                    state: CellState(character: "\u{2591}", color: .tint, bold: false)
                )
            }
        }
    }

    func renderContent(into grid: CharacterGrid) {
        let text = "HISTORY"
        let cols = GridMetrics.columns
        let centerRow = grid.rowCount / 2
        let startCol = max(0, (cols - text.count) / 2)

        for (i, ch) in text.enumerated() {
            grid.setCell(
                layer: .content, row: centerRow, col: startCol + i,
                state: CellState(character: ch, color: .bold, bold: true)
            )
        }
    }
}

@MainActor
final class OptionsPageRenderer: PageRenderer {
    let page: Page = .options
    let hiddenStructureRows: Set<Int> = []

    func renderStructure(into grid: CharacterGrid) {
        let cols = GridMetrics.columns
        for row in 0..<grid.rowCount {
            for col in 0..<cols {
                grid.setCell(
                    layer: .structure, row: row, col: col,
                    state: CellState(character: "\u{2591}", color: .tint, bold: false)
                )
            }
        }
    }

    func renderContent(into grid: CharacterGrid) {
        let text = "OPTIONS"
        let cols = GridMetrics.columns
        let centerRow = grid.rowCount / 2
        let startCol = max(0, (cols - text.count) / 2)

        for (i, ch) in text.enumerated() {
            grid.setCell(
                layer: .content, row: centerRow, col: startCol + i,
                state: CellState(character: ch, color: .bold, bold: true)
            )
        }
    }
}

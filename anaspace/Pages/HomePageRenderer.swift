import Foundation

@MainActor
final class HomePageRenderer: PageRenderer {
    let page: Page = .home
    let hiddenStructureRows: Set<Int> = Set(0..<10)

    var locationLabel: String = "OAKLAND, CA | USA"

    func renderStructure(into grid: CharacterGrid) {
        let cols = GridMetrics.columns

        for row in 0..<grid.rowCount {
            guard !hiddenStructureRows.contains(row) else { continue }
            for col in 0..<cols {
                grid.setCell(
                    layer: .structure, row: row, col: col,
                    state: CellState(character: "\u{2591}", color: .tint, bold: false)
                )
            }
        }
    }

    func renderContent(into grid: CharacterGrid) {
        // White X marker over map area
        grid.setCell(
            layer: .content, row: 3, col: 13,
            state: CellState(character: "\u{2573}", color: .highlight, bold: false)
        )

        // Location label below LOCATION button
        for (i, ch) in locationLabel.enumerated() {
            guard i < GridMetrics.columns else { break }
            grid.setCell(
                layer: .content, row: 9, col: i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }

        let text = "READY TO OBSERVE"
        let cols = GridMetrics.columns
        let centerRow = grid.rowCount / 2

        let totalWidth = 2 + text.count
        let startCol = max(0, (cols - totalWidth) / 2)

        grid.setCell(
            layer: .content, row: centerRow, col: startCol,
            state: CellState(character: "\u{25CF}", color: .focus, bold: true)
        )

        for (i, ch) in text.enumerated() {
            grid.setCell(
                layer: .content, row: centerRow, col: startCol + 2 + i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }
    }
}

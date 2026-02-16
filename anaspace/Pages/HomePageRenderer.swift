import Foundation

@MainActor
final class HomePageRenderer: PageRenderer {
    let page: Page = .home

    var hasObservations = false
    var locationLabel: String = "OAKLAND, CA | USA"
    var graphSubject = GraphSubject(label: "")
    var graphItems: [GraphItem] = []
    var connections: [CultureConnection] = []
    var placements: [PlacedItem] = []
    var bio: String = ""
    var birthInfo: String = ""

    var hiddenStructureRows: Set<Int> {
        hasObservations ? Set(0..<10) : []
    }

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
        guard hasObservations else {
            renderReadyState(into: grid)
            return
        }

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

        // Radial graph below map area
        let layout = RadialGraphLayout()
        placements = layout.render(
            subject: graphSubject,
            items: graphItems,
            into: grid,
            startRow: 11,
            endRow: grid.rowCount - 2
        )
    }

    // MARK: - Ready to Observe

    private func renderReadyState(into grid: CharacterGrid) {
        let cols = GridMetrics.columns
        let centerRow = grid.rowCount / 2
        let text = "\u{25CF}  READY TO OBSERVE"
        let startCol = max(0, (cols - text.count) / 2)

        for (i, ch) in text.enumerated() {
            guard startCol + i < cols else { break }
            let isGlyph = i == 0
            grid.setCell(
                layer: .content, row: centerRow, col: startCol + i,
                state: CellState(
                    character: ch,
                    color: isGlyph ? .focus : .bold,
                    bold: !isGlyph
                )
            )
        }
    }

}

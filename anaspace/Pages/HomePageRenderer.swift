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

    /// Circa year displayed on the "THIS SPOT" card, set externally by ContentView.
    var circaYear: Int = 1975

    /// Card tap regions: (row, col, width, height) for each of the 4 idea cards.
    var ideaCardRegions: [(row: Int, col: Int, width: Int, height: Int)] = []

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

        // "READY TO OBSERVE" — positioned at 1/3 down, shifted up 4
        let readyRow = grid.rowCount / 3 - 4
        let readyText = "\u{25CF}  READY TO OBSERVE"
        let readyCol = max(0, (cols - readyText.count) / 2)

        for (i, ch) in readyText.enumerated() {
            guard readyCol + i < cols else { break }
            let isGlyph = i == 0
            grid.setCell(
                layer: .content, row: readyRow, col: readyCol + i,
                state: CellState(
                    character: ch,
                    color: isGlyph ? .focus : .bold,
                    bold: false
                )
            )
        }

        // IDEAS section — 4 action cards
        renderIdeasSection(into: grid, readyRow: readyRow)
    }

    // MARK: - Ideas Section

    private func renderIdeasSection(into grid: CharacterGrid, readyRow: Int) {
        let cols = GridMetrics.columns
        let playerRow = grid.rowCount - 1

        // Card dimensions
        let cardWidth = 14
        let cardHeight = 4
        let leftCol = 1
        let rightCol = cols - cardWidth - 1

        // Position: center the block between readyRow and playerRow
        // Block: 2 (header+spacer) + 4 (top cards) + 2 (gap) + 4 (bottom cards) = 12 rows
        let blockHeight = 12
        let midpoint = readyRow + 2 + (playerRow - readyRow - 2 - blockHeight) / 2
        let ideasRow = midpoint
        let topCardRow = ideasRow + 2
        let bottomCardRow = topCardRow + cardHeight + 2

        // "IDEAS" header — centered
        let header = "IDEAS"
        let headerCol = max(0, (cols - header.count) / 2)
        for (i, ch) in header.enumerated() {
            guard headerCol + i < cols else { break }
            grid.setCell(
                layer: .content, row: ideasRow, col: headerCol + i,
                state: CellState(character: ch, color: .bold, bold: true, small: true)
            )
        }

        // Card content: (line1, line2)
        let cards: [(String, String)] = [
            ("WHAT'S HOT", "RIGHT HERE"),
            ("WHO SHAPED", "THIS PLACE"),
            ("THIS SPOT", "CIRCA \(circaYear)"),
            ("WORDS THAT", "MADE SONGS"),
        ]

        // Card positions: top-left, top-right, bottom-left, bottom-right
        let positions = [
            (row: topCardRow, col: leftCol),
            (row: topCardRow, col: rightCol),
            (row: bottomCardRow, col: leftCol),
            (row: bottomCardRow, col: rightCol),
        ]

        ideaCardRegions = []

        for (index, card) in cards.enumerated() {
            let pos = positions[index]
            renderCard(
                into: grid,
                row: pos.row, col: pos.col,
                width: cardWidth, height: cardHeight,
                line1: card.0, line2: card.1
            )
            ideaCardRegions.append((row: pos.row, col: pos.col, width: cardWidth, height: cardHeight))
        }
    }

    private func renderCard(
        into grid: CharacterGrid,
        row: Int, col: Int,
        width: Int, height: Int,
        line1: String, line2: String
    ) {
        guard row + height <= grid.rowCount else { return }

        // Top border: ┌     ┐
        grid.setCell(layer: .content, row: row, col: col,
                     state: CellState(character: "\u{250C}", color: .bold, bold: false))
        grid.setCell(layer: .content, row: row, col: col + width - 1,
                     state: CellState(character: "\u{2510}", color: .bold, bold: false))

        // Line 1: ╷ TEXT ╷
        grid.setCell(layer: .content, row: row + 1, col: col,
                     state: CellState(character: "\u{2502}", color: .bold, bold: false))
        for (i, ch) in line1.enumerated() {
            guard col + 2 + i < col + width - 1 else { break }
            grid.setCell(layer: .content, row: row + 1, col: col + 2 + i,
                         state: CellState(character: ch, color: .bold, bold: false))
        }
        grid.setCell(layer: .content, row: row + 1, col: col + width - 1,
                     state: CellState(character: "\u{2502}", color: .bold, bold: false))

        // Line 2: ╷ TEXT ╷
        grid.setCell(layer: .content, row: row + 2, col: col,
                     state: CellState(character: "\u{2502}", color: .bold, bold: false))
        for (i, ch) in line2.enumerated() {
            guard col + 2 + i < col + width - 1 else { break }
            grid.setCell(layer: .content, row: row + 2, col: col + 2 + i,
                         state: CellState(character: ch, color: .bold, bold: false))
        }
        grid.setCell(layer: .content, row: row + 2, col: col + width - 1,
                     state: CellState(character: "\u{2502}", color: .bold, bold: false))

        // Bottom border: └     ┘
        grid.setCell(layer: .content, row: row + 3, col: col,
                     state: CellState(character: "\u{2514}", color: .bold, bold: false))
        grid.setCell(layer: .content, row: row + 3, col: col + width - 1,
                     state: CellState(character: "\u{2518}", color: .bold, bold: false))
    }

}

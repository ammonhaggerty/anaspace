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

    private let sampleItems: [GraphItem] = [
        GraphItem(glyph: "\u{25A0}", label: "LARRY GRAHAM", relevance: 0.95),
        GraphItem(glyph: "\u{25A0}", label: "FREDDIE STONE", relevance: 0.9),
        GraphItem(glyph: "\u{25A0}", label: "ROSE STONE", relevance: 0.85),
        GraphItem(glyph: "\u{25AA}", label: "MILES DAVIS", relevance: 0.7),
        GraphItem(glyph: "\u{21A2}", label: "JAMES BROWN", relevance: 0.65),
        GraphItem(glyph: "\u{21A3}", label: "PRINCE", relevance: 0.6),
        GraphItem(glyph: "\u{2B58}", label: "STAND!", relevance: 0.8),
        GraphItem(glyph: "\u{2B58}", label: "THERE'S A RIOT GOIN' ON", relevance: 0.75),
        GraphItem(glyph: "\u{2207}", label: "SAN FRANCISCO", relevance: 0.5),
        GraphItem(glyph: "\u{26A1}", label: "WOODSTOCK 1969", relevance: 0.55),
        GraphItem(glyph: "\u{224B}", label: "PSYCHEDELIC SOUL", relevance: 0.45),
    ]

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

        // Radial graph below map area
        let layout = RadialGraphLayout()
        layout.render(
            subject: GraphSubject(label: "SLY STONE"),
            items: sampleItems,
            into: grid,
            startRow: 11,
            endRow: grid.rowCount - 1
        )
    }
}

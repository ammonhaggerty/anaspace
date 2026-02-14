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

    /// Row positions of settings labels, populated after render.
    private(set) var settingsRows: [Int] = []

    private let layout = FormalContentLayout()

    private let sections: [ContentSection] = [
        .spacer,
        .header("ANASPACE"),
        .spacer,
        .header("KEY"),
        .spacer,
        .splitColumns([
            ("\u{25A0}", "COLLABORATOR"),  // ■
            ("\u{25AA}", "PEER"),           // ▪
            ("\u{21A2}", "INFLUENCE"),      // ↢
            ("\u{21A3}", "FOLLOWER"),       // ↣
            ("\u{2B58}", "CREATION"),       // ⭘
            ("\u{2207}", "PLACE"),          // ∇
            ("\u{26A1}", "EVENT"),          // ⚡
            ("\u{224B}", "MOVEMENT"),       // ≋
        ]),
        .spacer,
        .header("SETTINGS"),
        .spacer,
        .settingsLabel("LOG OUT"),
        .spacer,
        .settingsLabel("UNLINK"),
        .spacer,
        .settingsLabel("DOWNLOAD DATA"),
    ]

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
        // Track settings label rows
        settingsRows = []
        var row = 0

        for section in sections {
            guard row < grid.rowCount else { break }

            switch section {
            case .settingsLabel:
                settingsRows.append(row)
                row = layout.render(sections: [section], into: grid, startRow: row)
            default:
                row = layout.render(sections: [section], into: grid, startRow: row)
            }
        }
    }
}

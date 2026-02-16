import Foundation

@MainActor
final class HistoryPageRenderer: PageRenderer {
    let page: Page = .history
    let hiddenStructureRows: Set<Int> = []

    var entries: [HistoryEntry] = []

    /// Row index of each entry, populated during renderContent for tap overlays.
    private(set) var entryRows: [Int] = []

    private let layout = FormalContentLayout()

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
        entryRows = []
        var row = 0

        // Row 0: spacer
        row += 1

        // Row 1: header
        let header = "\u{21A9} HISTORY"
        for (i, ch) in header.enumerated() {
            guard i < 31 else { break }
            grid.setCell(
                layer: .content, row: row, col: 1 + i,
                state: CellState(character: ch, color: .bold, bold: true)
            )
        }
        row += 1

        // Row 2: spacer
        row += 1

        // Entry rows: each entry = 1 text row + 1 spacer
        for entry in entries {
            guard row < grid.rowCount else { break }

            entryRows.append(row)
            let line = entry.displayLine
            for (i, ch) in line.enumerated() {
                guard 1 + i < GridMetrics.columns else { break }
                grid.setCell(
                    layer: .content, row: row, col: 1 + i,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
            }
            row += 1

            // Spacer after entry
            row += 1
        }
    }
}

@MainActor
final class OptionsPageRenderer: PageRenderer {
    let page: Page = .options
    let hiddenStructureRows: Set<Int> = []

    /// Row positions of settings labels, populated after render.
    private(set) var settingsRows: [Int] = []

    /// Set before rendering to reflect current autoplay state.
    var autoplayEnabled: Bool = false

    private let layout = FormalContentLayout()

    private var sections: [ContentSection] {
        let autoplayLabel = autoplayEnabled ? "AUTOPLAY   ON" : "AUTOPLAY  OFF"
        return [
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
            .settingsLabel(autoplayLabel),
            .spacer,
            .settingsLabel("LOG OUT"),
            .spacer,
            .settingsLabel("UNLINK"),
            .spacer,
            .settingsLabel("DOWNLOAD DATA"),
        ]
    }

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

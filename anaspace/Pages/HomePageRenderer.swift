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
    var showNothingObserved = false

    /// Circa year displayed on the "THIS SPOT" card, set externally by ContentView.
    var circaYear: Int = 1975

    /// Card tap regions: (row, col, width, height) for each of the 4 idea cards.
    var ideaCardRegions: [(row: Int, col: Int, width: Int, height: Int)] = []
    /// Card text content for each idea card (for pressed-state re-rendering).
    private(set) var ideaCardTexts: [(String, String)] = []

    /// Subject bracket region in the radial graph (for pressed-state re-rendering).
    private(set) var subjectBracketRegion: (row: Int, col: Int, width: Int, height: Int) = (-1, 0, 0, 0)
    private(set) var subjectDisplayText: String = ""

    var hiddenStructureRows: Set<Int> {
        hasObservations ? Set(0..<11) : []
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

        // Radial graph below map area (starts at row 12, skipping one row gap)
        let layout = RadialGraphLayout()
        placements = layout.render(
            subject: graphSubject,
            items: graphItems,
            into: grid,
            startRow: 12,
            endRow: grid.rowCount - 2
        )

        // Compute subject bracket region for pressed-state rendering
        let graphStartRow = 12
        let graphEndRow = grid.rowCount - 2
        let areaRows = graphEndRow - graphStartRow + 1
        let centerRow = areaRows / 2 - 1
        let centerCol = GridMetrics.columns / 2

        let subjectLabel = graphSubject.label.uppercased()
        if let firstLine = TextWrapper.wrap(subjectLabel, maxWidth: 26, maxLines: 1).first {
            subjectDisplayText = firstLine
        } else {
            subjectDisplayText = String(subjectLabel.prefix(26))
        }
        let subLabelStart = max(1, centerCol - subjectDisplayText.count / 2)
        let bracketCol = max(1, subLabelStart - 2)
        let bracketWidth = subjectDisplayText.count + 4
        subjectBracketRegion = (row: graphStartRow + centerRow, col: bracketCol, width: bracketWidth, height: 3)
    }

    // MARK: - Ready to Observe

    private func renderReadyState(into grid: CharacterGrid) {
        let cols = GridMetrics.columns
        let readyRow = grid.rowCount / 3 - 4

        if showNothingObserved {
            // ⨀ glyph centered above text
            let glyphCol = cols / 2
            grid.setCell(
                layer: .content, row: readyRow - 1, col: glyphCol,
                state: CellState(character: "\u{2A00}", color: .bold, bold: false)
            )

            // NOTHING OBSERVED (bold) + guidance lines
            let lines: [(text: String, isBold: Bool)] = [
                ("NOTHING OBSERVED", true),
                ("TRY AN IDEA OR", false),
                ("TAP/HOLD TO SPEAK", false),
            ]
            for (lineIndex, line) in lines.enumerated() {
                let row = readyRow + lineIndex
                let col = max(0, (cols - line.text.count) / 2)
                for (i, ch) in line.text.enumerated() {
                    guard col + i < cols else { break }
                    grid.setCell(
                        layer: .content, row: row, col: col + i,
                        state: CellState(character: ch, color: .bold, bold: line.isBold)
                    )
                }
            }
        } else {
            // Circle glyph — centered, one row above the text (pulsed by IdlePulseAnimation)
            let circleCol = cols / 2
            grid.setCell(
                layer: .content, row: readyRow - 1, col: circleCol,
                state: CellState(character: "\u{25CF}", color: .focus, bold: false)
            )

            // "READY TO OBSERVE" — centered
            let readyText = "READY TO OBSERVE"
            let readyCol = max(0, (cols - readyText.count) / 2)
            for (i, ch) in readyText.enumerated() {
                guard readyCol + i < cols else { break }
                grid.setCell(
                    layer: .content, row: readyRow, col: readyCol + i,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
            }
        }

        // IDEAS section — 4 action cards
        renderIdeasSection(into: grid, readyRow: readyRow)
    }

    // MARK: - Ideas Section

    private func renderIdeasSection(into grid: CharacterGrid, readyRow: Int) {
        let cols = GridMetrics.columns
        let playerRow = grid.rowCount - 1

        // Card content: (line1, line2)
        let cards: [(String, String)] = [
            ("WHAT'S HOT", "RIGHT HERE"),
            ("WHO SHAPED", "THIS PLACE"),
            ("THIS SPOT", "CIRCA \(circaYear)"),
            ("WORDS THAT", "MADE SONGS"),
        ]
        ideaCardTexts = cards

        // Card dimensions (derived from text)
        let maxTextWidth = cards.flatMap { [$0.0, $0.1] }.map(\.count).max() ?? 10
        let cardWidth = maxTextWidth + 4
        let cardHeight = 4  // 2 text lines + 2 border rows
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
            let size = BracketButton.render(
                into: grid,
                row: pos.row, col: pos.col,
                lines: [card.0, card.1]
            )
            ideaCardRegions.append((row: pos.row, col: pos.col, width: size.width, height: size.height))
        }
    }

    // MARK: - Pressed State Rendering

    func renderIdeaCardPressed(index: Int, into grid: CharacterGrid) {
        guard index < ideaCardRegions.count, index < ideaCardTexts.count else { return }
        let region = ideaCardRegions[index]
        let texts = ideaCardTexts[index]
        BracketButton.render(into: grid, row: region.row, col: region.col,
                             lines: [texts.0, texts.1], pressed: true)
    }

    func renderSubjectPressed(into grid: CharacterGrid) {
        guard subjectBracketRegion.row >= 0 else { return }
        BracketButton.render(
            into: grid,
            row: subjectBracketRegion.row,
            col: subjectBracketRegion.col,
            lines: [subjectDisplayText],
            glyph: (character: "\u{25CF}", color: .focus),
            pressed: true
        )
    }

}

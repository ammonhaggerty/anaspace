import Foundation

@MainActor
final class HistoryPageRenderer: PageRenderer {
    let page: Page = .history
    let hiddenStructureRows: Set<Int> = []

    var entries: [HistoryEntry] = []

    /// Row index of each entry, populated during renderContent for tap overlays.
    private(set) var entryRows: [Int] = []

    /// Row range of the reset button (top row of 3-row bracket).
    private(set) var resetButtonRow: Int = -1

    private let layout = FormalContentLayout()
    private let insetCol = 1
    private let contentWidth = 31

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
        resetButtonRow = -1
        var row = 0

        // Row 0: spacer
        row += 1

        // Rows 1-3: Reset button with bracket decoration
        row = renderResetButton(into: grid, startRow: row)

        // Spacer
        row += 1

        // Header
        let header = "\u{21A9} HISTORY"
        for (i, ch) in header.enumerated() {
            guard i < contentWidth else { break }
            grid.setCell(
                layer: .content, row: row, col: insetCol + i,
                state: CellState(character: ch, color: .bold, bold: true)
            )
        }
        row += 1

        // Spacer
        row += 1

        // Entry rows: each entry = 1 text row + 1 spacer
        for entry in entries {
            guard row < grid.rowCount else { break }

            entryRows.append(row)
            let line = entry.displayLine
            for (i, ch) in line.enumerated() {
                guard insetCol + i < GridMetrics.columns else { break }
                grid.setCell(
                    layer: .content, row: row, col: insetCol + i,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
            }
            row += 1

            // Spacer after entry
            row += 1
        }
    }

    // MARK: - Reset Button

    private func renderResetButton(into grid: CharacterGrid, startRow: Int) -> Int {
        guard startRow + 2 < grid.rowCount else { return startRow }

        resetButtonRow = startRow

        let text = "RESET TO OBSERVE PAGE"
        let bracketLeft = insetCol
        let bracketRight = insetCol + contentWidth - 1

        // Row 1: top bracket corners
        grid.setCell(
            layer: .content, row: startRow, col: bracketLeft,
            state: CellState(character: "\u{250C}", color: .bold, bold: false)  // ┌
        )
        grid.setCell(
            layer: .content, row: startRow, col: bracketRight,
            state: CellState(character: "\u{2510}", color: .bold, bold: false)  // ┐
        )

        // Row 2: bracket extensions + text centered
        let textRow = startRow + 1
        let innerWidth = bracketRight - bracketLeft - 1  // cols available between brackets
        let leftPad = (innerWidth - text.count) / 2

        grid.setCell(
            layer: .content, row: textRow, col: bracketLeft,
            state: CellState(character: "\u{2502}", color: .bold, bold: false)  // │
        )
        grid.setCell(
            layer: .content, row: textRow, col: bracketRight,
            state: CellState(character: "\u{2502}", color: .bold, bold: false)  // │
        )

        for (i, ch) in text.enumerated() {
            grid.setCell(
                layer: .content, row: textRow, col: bracketLeft + 1 + leftPad + i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }

        // Row 3: bottom bracket corners
        grid.setCell(
            layer: .content, row: startRow + 2, col: bracketLeft,
            state: CellState(character: "\u{2514}", color: .bold, bold: false)  // └
        )
        grid.setCell(
            layer: .content, row: startRow + 2, col: bracketRight,
            state: CellState(character: "\u{2518}", color: .bold, bold: false)  // ┘
        )

        return startRow + 3
    }
}

@MainActor
final class OptionsPageRenderer: PageRenderer {
    let page: Page = .options
    let hiddenStructureRows: Set<Int> = []

    /// Set before rendering to reflect current autoplay state.
    var autoplayEnabled: Bool = false

    /// Row where "[GITHUB REPOSITORY]" link text is rendered.
    private(set) var githubLinkRow: Int = -1
    /// Column range of the link text (inclusive).
    private(set) var githubLinkStartCol: Int = 0
    private(set) var githubLinkEndCol: Int = 0

    /// Row of the autoplay toggle.
    private(set) var toggleRow: Int = -1
    /// Starting column of toggle graphics.
    private(set) var toggleStartCol: Int = 0

    private let layout = FormalContentLayout()
    private let insetCol = 1
    private let contentWidth = 31

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
        // Reset tap regions
        githubLinkRow = -1
        toggleRow = -1

        var row = 0

        // Spacer
        row += 1

        // ANASPACE header
        row = layout.render(sections: [.header("ANASPACE")], into: grid, startRow: row)

        // Spacer
        row += 1

        // Paragraph with bold [GITHUB REPOSITORY] link
        row = renderAboutParagraph(into: grid, startRow: row)

        // Two spacers
        row += 2

        // KEY header
        row = layout.render(sections: [.header("KEY")], into: grid, startRow: row)

        // Spacer
        row += 1

        // Entity type legend
        row = layout.render(sections: [
            .splitColumns([
                ("\u{25A0}", "COLLABORATOR"),  // blackbox
                ("\u{25AA}", "PEER"),           // small black square
                ("\u{00AB}", "INFLUENCE"),      // left-pointing double angle
                ("\u{00BB}", "FOLLOWER"),       // right-pointing double angle
                ("\u{25CB}", "CREATION"),       // white circle
                ("\u{2207}", "PLACE"),          // nabla
                ("\u{26A1}", "EVENT"),          // lightning
                ("\u{2248}", "MOVEMENT"),       // almost equal to
            ]),
        ], into: grid, startRow: row)

        // Two spacers
        row += 2

        // SETTINGS header
        row = layout.render(sections: [.header("SETTINGS")], into: grid, startRow: row)

        // Spacer
        row += 1

        // Autoplay toggle
        row = renderAutoplayToggle(into: grid, startRow: row)
    }

    // MARK: - About Paragraph

    private func renderAboutParagraph(into grid: CharacterGrid, startRow: Int) -> Int {
        let text = "CREATED BY AMMON HAGGERTY FOR THE CLAUDE CODE WEEK-LONG HACKATHON IN FEBRUARY 2026. MORE ABOUT THIS PROJECT IN THE [GITHUB REPOSITORY]"
        let linkMarker = "[GITHUB REPOSITORY]"
        let lines = TextWrapper.wrap(text, maxWidth: contentWidth)
        var currentRow = startRow

        for line in lines {
            guard currentRow < grid.rowCount else { break }

            // Check if this line contains the link marker
            let linkRange = line.range(of: linkMarker)

            for (i, ch) in line.enumerated() {
                let isLink: Bool
                if let range = linkRange {
                    let charIndex = line.index(line.startIndex, offsetBy: i)
                    isLink = range.contains(charIndex)
                } else {
                    isLink = false
                }

                grid.setCell(
                    layer: .content, row: currentRow, col: insetCol + i,
                    state: CellState(
                        character: ch,
                        color: .bold,
                        bold: isLink
                    )
                )
            }

            // Track link row for tap overlay
            if linkRange != nil {
                githubLinkRow = currentRow
                let startOffset = line.distance(from: line.startIndex, to: linkRange!.lowerBound)
                let endOffset = startOffset + linkMarker.count - 1
                githubLinkStartCol = insetCol + startOffset
                githubLinkEndCol = insetCol + endOffset
            }

            currentRow += 1
        }

        return currentRow
    }

    // MARK: - Autoplay Toggle

    private func renderAutoplayToggle(into grid: CharacterGrid, startRow: Int) -> Int {
        guard startRow < grid.rowCount else { return startRow }

        toggleRow = startRow

        let label = "AUTO-PLAY MUSIC"

        // Single toggle that shows current state:
        // ON:  [◯|◉  ON]  — active glyph on right
        // OFF: [◉|◯ OFF]  — active glyph on left
        let active: Character = "\u{25C9}"    // ◉ fisheye
        let inactive: Character = "\u{25EF}"  // ◯ large circle

        let toggleChars: [Character]
        let labelText: String
        if autoplayEnabled {
            toggleChars = ["[", inactive, "|", active, " ", " "]
            labelText = "ON"
        } else {
            toggleChars = ["[", active, "|", inactive, " "]
            labelText = "OFF"
        }

        let toggleWidth = toggleChars.count + labelText.count + 1  // +1 for closing ]
        let toggleCol = insetCol + contentWidth - toggleWidth
        toggleStartCol = toggleCol

        // Render label
        for (i, ch) in label.enumerated() {
            grid.setCell(
                layer: .content, row: startRow, col: insetCol + i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }

        // Render toggle graphic
        var col = toggleCol
        for ch in toggleChars {
            grid.setCell(
                layer: .content, row: startRow, col: col,
                state: CellState(character: ch, color: .bold, bold: false)
            )
            col += 1
        }

        // Render label text (bold)
        for ch in labelText {
            grid.setCell(
                layer: .content, row: startRow, col: col,
                state: CellState(character: ch, color: .bold, bold: true)
            )
            col += 1
        }

        // Closing bracket
        grid.setCell(
            layer: .content, row: startRow, col: col,
            state: CellState(character: "]", color: .bold, bold: false)
        )

        return startRow + 1
    }
}

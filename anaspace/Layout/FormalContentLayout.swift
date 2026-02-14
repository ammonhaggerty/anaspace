import Foundation

// MARK: - Content Section Model

enum ContentSection {
    case header(String)
    case paragraph(String)
    case splitColumns([(Character, String)])
    case settingsLabel(String)
    case spacer
}

// MARK: - Formal Content Layout

@MainActor
struct FormalContentLayout {
    let insetCol: Int = 1
    let contentWidth: Int = 31

    /// Renders sections into grid starting at `startRow`.
    /// Returns the next available row after all content.
    @discardableResult
    func render(
        sections: [ContentSection],
        into grid: CharacterGrid,
        startRow: Int
    ) -> Int {
        var row = startRow

        for section in sections {
            guard row < grid.rowCount else { break }

            switch section {
            case .header(let text):
                row = renderHeader(text, into: grid, row: row)

            case .paragraph(let text):
                row = renderParagraph(text, into: grid, row: row)

            case .splitColumns(let pairs):
                row = renderSplitColumns(pairs, into: grid, row: row)

            case .settingsLabel(let text):
                row = renderSettingsLabel(text, into: grid, row: row)

            case .spacer:
                row += 1
            }
        }

        return row
    }

    // MARK: - Section Renderers

    private func renderHeader(_ text: String, into grid: CharacterGrid, row: Int) -> Int {
        let uppercased = text.uppercased()
        for (i, ch) in uppercased.enumerated() {
            guard i < contentWidth else { break }
            grid.setCell(
                layer: .content, row: row, col: insetCol + i,
                state: CellState(character: ch, color: .bold, bold: true)
            )
        }
        return row + 1
    }

    private func renderParagraph(_ text: String, into grid: CharacterGrid, row: Int) -> Int {
        let lines = TextWrapper.wrap(text, maxWidth: contentWidth)
        var currentRow = row
        for line in lines {
            guard currentRow < grid.rowCount else { break }
            for (i, ch) in line.enumerated() {
                grid.setCell(
                    layer: .content, row: currentRow, col: insetCol + i,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
            }
            currentRow += 1
        }
        return currentRow
    }

    private func renderSplitColumns(_ pairs: [(Character, String)], into grid: CharacterGrid, row: Int) -> Int {
        let leftColStart = insetCol
        let rightColStart = insetCol + 16  // cols 17–31
        let colWidth = 15
        var currentRow = row

        var index = 0
        while index < pairs.count {
            guard currentRow < grid.rowCount else { break }

            // Left column entry
            let (leftGlyph, leftLabel) = pairs[index]
            renderGlyphLabel(
                glyph: leftGlyph,
                label: leftLabel.uppercased(),
                into: grid,
                row: currentRow,
                col: leftColStart,
                maxWidth: colWidth
            )

            // Right column entry (if available)
            if index + 1 < pairs.count {
                let (rightGlyph, rightLabel) = pairs[index + 1]
                renderGlyphLabel(
                    glyph: rightGlyph,
                    label: rightLabel.uppercased(),
                    into: grid,
                    row: currentRow,
                    col: rightColStart,
                    maxWidth: colWidth
                )
            }

            index += 2
            currentRow += 1
        }

        return currentRow
    }

    private func renderGlyphLabel(
        glyph: Character,
        label: String,
        into grid: CharacterGrid,
        row: Int,
        col: Int,
        maxWidth: Int
    ) {
        // Glyph + space + label
        grid.setCell(
            layer: .content, row: row, col: col,
            state: CellState(character: glyph, color: .bold, bold: false)
        )
        grid.setCell(
            layer: .content, row: row, col: col + 1,
            state: CellState(character: " ", color: .clear, bold: false)
        )
        let maxLabelWidth = maxWidth - 2
        for (i, ch) in label.prefix(maxLabelWidth).enumerated() {
            grid.setCell(
                layer: .content, row: row, col: col + 2 + i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }
    }

    private func renderSettingsLabel(_ text: String, into grid: CharacterGrid, row: Int) -> Int {
        let uppercased = text.uppercased()
        for (i, ch) in uppercased.enumerated() {
            guard i < contentWidth else { break }
            grid.setCell(
                layer: .content, row: row, col: insetCol + i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }
        return row + 1
    }
}

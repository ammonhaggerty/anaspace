import Foundation

@MainActor
enum BracketButton {

    /// Renders a bracket-enclosed button into the character grid.
    ///
    /// Layout (1 cell padding each side):
    /// ```
    /// ┌         ┐     ← top border (optional glyph centered here)
    /// │ LINE 1  │     ← text row(s)
    /// │ LINE 2  │
    /// └         ┘     ← bottom border
    /// ```
    ///
    /// - Returns: The size of the rendered button (width, height).
    @discardableResult
    static func render(
        into grid: CharacterGrid,
        layer: GridLayer = .content,
        row: Int, col: Int,
        lines: [String],
        glyph: (character: Character, color: GridColor)? = nil,
        pressed: Bool = false,
        color: GridColor = .bold
    ) -> (width: Int, height: Int) {
        let maxLineWidth = lines.map(\.count).max() ?? 0
        let width = maxLineWidth + 4
        let height = lines.count + 2

        guard row + height <= grid.rowCount else { return (width, height) }

        // Border glyphs
        let tl: Character = pressed ? "\u{2554}" : "\u{250C}"
        let tr: Character = pressed ? "\u{2557}" : "\u{2510}"
        let bl: Character = pressed ? "\u{255A}" : "\u{2514}"
        let br: Character = pressed ? "\u{255D}" : "\u{2518}"
        let side: Character = pressed ? "\u{2551}" : "\u{2502}"

        // Top border
        grid.setCell(layer: layer, row: row, col: col,
                     state: CellState(character: tl, color: color, bold: false))
        grid.setCell(layer: layer, row: row, col: col + width - 1,
                     state: CellState(character: tr, color: color, bold: false))

        // Centered glyph on top border row
        if let glyph {
            let glyphCol = col + width / 2
            grid.setCell(layer: layer, row: row, col: glyphCol,
                         state: CellState(character: glyph.character, color: glyph.color, bold: pressed))
        }

        // Text rows
        for (lineIndex, line) in lines.enumerated() {
            let textRow = row + 1 + lineIndex
            grid.setCell(layer: layer, row: textRow, col: col,
                         state: CellState(character: side, color: color, bold: false))
            for (i, ch) in line.enumerated() {
                guard col + 2 + i < col + width - 1 else { break }
                grid.setCell(layer: layer, row: textRow, col: col + 2 + i,
                             state: CellState(character: ch, color: color, bold: pressed))
            }
            grid.setCell(layer: layer, row: textRow, col: col + width - 1,
                         state: CellState(character: side, color: color, bold: false))
        }

        // Bottom border
        grid.setCell(layer: layer, row: row + height - 1, col: col,
                     state: CellState(character: bl, color: color, bold: false))
        grid.setCell(layer: layer, row: row + height - 1, col: col + width - 1,
                     state: CellState(character: br, color: color, bold: false))

        return (width, height)
    }
}

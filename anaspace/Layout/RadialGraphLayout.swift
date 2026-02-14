import Foundation

// MARK: - Data Model

struct GraphSubject {
    let label: String
}

struct GraphItem {
    let glyph: Character
    let label: String
    let relevance: Float  // 0.0–1.0 (1.0 = most relevant, placed closest)
}

// MARK: - Occupancy Grid

private struct OccupancyGrid {
    private var occupied: [[Bool]]
    let rows: Int
    let cols: Int

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.occupied = Array(repeating: Array(repeating: false, count: cols), count: rows)
    }

    /// Check placement with asymmetric padding: `hPad` cols horizontal, `vPad` rows vertical.
    func canPlace(row: Int, col: Int, width: Int, height: Int, hPad: Int = 2, vPad: Int = 1) -> Bool {
        let minR = row - vPad
        let maxR = row + height - 1 + vPad
        let minC = col - hPad
        let maxC = col + width - 1 + hPad

        for r in minR...maxR {
            for c in minC...maxC {
                guard r >= 0, r < rows, c >= 0, c < cols else {
                    if r >= row, r < row + height, c >= col, c < col + width {
                        return false
                    }
                    continue
                }
                if occupied[r][c] { return false }
            }
        }
        return true
    }

    mutating func mark(row: Int, col: Int, width: Int, height: Int) {
        for r in row..<(row + height) {
            for c in col..<(col + width) {
                guard r >= 0, r < rows, c >= 0, c < cols else { continue }
                occupied[r][c] = true
            }
        }
    }
}

// MARK: - Radial Graph Layout

@MainActor
struct RadialGraphLayout {

    // Aspect ratio: cols are narrower than rows are tall in the monospace grid
    private let colScale: Float = 0.6

    func render(
        subject: GraphSubject,
        items: [GraphItem],
        into grid: CharacterGrid,
        startRow: Int,
        endRow: Int
    ) {
        let areaRows = endRow - startRow + 1
        let areaCols = GridMetrics.columns
        guard areaRows > 4, areaCols > 4 else { return }

        // 1-cell inset margin on all sides
        let minRow = 1
        let maxRow = areaRows - 2
        let minCol = 1
        let maxCol = areaCols - 2

        var occupancy = OccupancyGrid(rows: areaRows, cols: areaCols)

        let centerRow = areaRows / 2 - 1
        let centerCol = areaCols / 2

        // --- Place subject (● glyph + bold label) ---

        let subjectLabel = subject.label.uppercased()
        let subjectText: String
        if let firstLine = TextWrapper.wrap(subjectLabel, maxWidth: 14, maxLines: 1).first {
            subjectText = firstLine
        } else {
            subjectText = String(subjectLabel.prefix(14))
        }

        let subLabelStart = max(minCol, centerCol - subjectText.count / 2)
        let subGlyphCol = subLabelStart + subjectText.count / 2

        grid.setCell(
            layer: .content,
            row: startRow + centerRow,
            col: subGlyphCol,
            state: CellState(character: "\u{25CF}", color: .focus, bold: true)
        )
        occupancy.mark(row: centerRow, col: subGlyphCol, width: 1, height: 1)

        let subLabelRow = centerRow + 1
        if subLabelRow <= maxRow {
            for (i, ch) in subjectText.enumerated() {
                let c = subLabelStart + i
                guard c <= maxCol else { break }
                grid.setCell(
                    layer: .content,
                    row: startRow + subLabelRow,
                    col: c,
                    state: CellState(character: ch, color: .bold, bold: true)
                )
            }
            occupancy.mark(
                row: subLabelRow, col: subLabelStart,
                width: min(subjectText.count, maxCol - subLabelStart + 1), height: 1
            )
        }

        // --- Place items ---

        let sorted = items.sorted { $0.relevance > $1.relevance }
        let halfHeight = Float(centerRow - minRow)

        // Golden ratio for horizontal variety
        let goldenRatio: Float = 1.618034

        for (index, item) in sorted.enumerated() {
            let lines = TextWrapper.wrap(item.label, maxWidth: 14, maxLines: 2)
            guard !lines.isEmpty else { continue }

            let textWidth = lines.map(\.count).max() ?? 1
            let blockH = 1 + lines.count  // glyph row + text rows

            // Target row distance from center: relevance 1.0 → 2 rows, 0.0 → edge
            let rowDist = Int(round(2.0 + (1.0 - item.relevance) * (halfHeight - 2.0)))

            // Always target above center first; overflow spills below
            let targetRow = centerRow - rowDist

            // Column bias from golden ratio — spreads items left/right organically
            let colBias = Float(index) * goldenRatio
            let biasedCol = Int(Float(minCol) + colBias.truncatingRemainder(dividingBy: Float(maxCol - minCol)))

            var placed = false

            // Search: try target row, then expand — prefer upward before downward
            for rowOffset in 0..<areaRows {
                guard !placed else { break }

                let tryRows: [Int]
                if rowOffset == 0 {
                    tryRows = [targetRow]
                } else {
                    // Try upward first (toward top of page), then downward
                    tryRows = [targetRow - rowOffset, targetRow + rowOffset]
                }

                for tryRow in tryRows {
                    guard !placed else { break }
                    guard tryRow >= minRow, tryRow + blockH - 1 <= maxRow else { continue }

                    // Sweep columns starting from biased position, alternating left/right
                    for colOffset in 0...(maxCol - minCol) {
                        guard !placed else { break }
                        let tryCols: [Int]
                        if colOffset == 0 {
                            tryCols = [biasedCol]
                        } else {
                            tryCols = [biasedCol + colOffset, biasedCol - colOffset]
                        }

                        for rawCol in tryCols {
                            guard !placed else { break }
                            // rawCol is the center target; derive text left col
                            var textCol = rawCol - textWidth / 2
                            textCol = max(minCol, min(maxCol - textWidth + 1, textCol))

                            let glyphC = max(minCol, min(maxCol, textCol + textWidth / 2))
                            let blockLeft = min(glyphC, textCol)
                            let blockRight = max(glyphC, textCol + textWidth - 1)
                            let blockW = blockRight - blockLeft + 1

                            guard blockLeft >= minCol, blockRight <= maxCol else { continue }

                            guard occupancy.canPlace(
                                row: tryRow, col: blockLeft,
                                width: blockW, height: blockH
                            ) else { continue }

                            // --- Render ---

                            grid.setCell(
                                layer: .content,
                                row: startRow + tryRow,
                                col: glyphC,
                                state: CellState(character: item.glyph, color: .bold, bold: false)
                            )

                            for (lineIdx, line) in lines.enumerated() {
                                let r = tryRow + 1 + lineIdx
                                guard r <= maxRow else { break }
                                for (charIdx, ch) in line.enumerated() {
                                    let c = textCol + charIdx
                                    guard c <= maxCol else { break }
                                    grid.setCell(
                                        layer: .content,
                                        row: startRow + r,
                                        col: c,
                                        state: CellState(character: ch, color: .bold, bold: false)
                                    )
                                }
                            }

                            occupancy.mark(
                                row: tryRow, col: blockLeft,
                                width: blockW, height: blockH
                            )
                            placed = true
                            break
                        }
                    }
                }
            }
        }
    }
}

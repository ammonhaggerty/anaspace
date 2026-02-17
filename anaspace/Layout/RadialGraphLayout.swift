import Foundation

// MARK: - Data Model

struct GraphSubject {
    let label: String
}

struct GraphItem {
    let glyph: Character
    let label: String
    let subtitle: String?
    let relevance: Float  // 0.0–1.0 (1.0 = most relevant, placed closest)

    init(glyph: Character, label: String, subtitle: String? = nil, relevance: Float) {
        self.glyph = glyph
        self.label = label
        self.subtitle = subtitle
        self.relevance = relevance
    }
}

// MARK: - Placement Result

struct PlacedItem: Identifiable {
    let index: Int       // Index into the original items array
    let row: Int         // Grid row (absolute, including startRow offset)
    let col: Int         // Grid column (left edge of block)
    let width: Int       // Block width in columns
    let height: Int      // Block height in rows

    var id: Int { index }
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

    private let goldenRatio: Float = 1.618034

    @discardableResult
    func render(
        subject: GraphSubject,
        items: [GraphItem],
        into grid: CharacterGrid,
        startRow: Int,
        endRow: Int
    ) -> [PlacedItem] {
        let areaRows = endRow - startRow + 1
        let areaCols = GridMetrics.columns
        guard areaRows > 4, areaCols > 4 else { return [] }

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
        if let firstLine = TextWrapper.wrap(subjectLabel, maxWidth: 26, maxLines: 1).first {
            subjectText = firstLine
        } else {
            subjectText = String(subjectLabel.prefix(26))
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

        // --- Bracket decoration around subject ---
        let bracketLeft = max(minCol, subLabelStart - 2)
        let bracketRight = min(maxCol, subLabelStart + subjectText.count + 1)

        // Top bracket corners (same row as glyph)
        grid.setCell(
            layer: .content, row: startRow + centerRow, col: bracketLeft,
            state: CellState(character: "\u{250C}", color: .bold, bold: false)  // ┌
        )
        grid.setCell(
            layer: .content, row: startRow + centerRow, col: bracketRight,
            state: CellState(character: "\u{2510}", color: .bold, bold: false)  // ┐
        )
        occupancy.mark(row: centerRow, col: bracketLeft, width: 1, height: 1)
        occupancy.mark(row: centerRow, col: bracketRight, width: 1, height: 1)

        // Middle bracket extensions (same row as label)
        if subLabelRow <= maxRow {
            grid.setCell(
                layer: .content, row: startRow + subLabelRow, col: bracketLeft,
                state: CellState(character: "\u{2502}", color: .bold, bold: false)  // │
            )
            grid.setCell(
                layer: .content, row: startRow + subLabelRow, col: bracketRight,
                state: CellState(character: "\u{2502}", color: .bold, bold: false)  // │
            )
        }

        // Bottom bracket corners (one row below label)
        let bottomBracketRow = subLabelRow + 1
        if bottomBracketRow <= maxRow {
            grid.setCell(
                layer: .content, row: startRow + bottomBracketRow, col: bracketLeft,
                state: CellState(character: "\u{2514}", color: .bold, bold: false)  // └
            )
            grid.setCell(
                layer: .content, row: startRow + bottomBracketRow, col: bracketRight,
                state: CellState(character: "\u{2518}", color: .bold, bold: false)  // ┘
            )
            occupancy.mark(row: bottomBracketRow, col: bracketLeft, width: 1, height: 1)
            occupancy.mark(row: bottomBracketRow, col: bracketRight, width: 1, height: 1)
        }

        // --- Place items ---

        var placements: [PlacedItem] = []
        let sorted = items.enumerated()
            .sorted { $0.element.relevance > $1.element.relevance }
        let halfHeight = Float(centerRow - minRow)

        for (index, entry) in sorted.enumerated() {
            let originalIndex = entry.offset
            let item = entry.element
            let lines = TextWrapper.wrap(item.label, maxWidth: 14, maxLines: 2)
            guard !lines.isEmpty else { continue }

            let subtitleLines: [String]
            if let subtitle = item.subtitle {
                subtitleLines = TextWrapper.wrap(subtitle, maxWidth: 14, maxLines: 1)
            } else {
                subtitleLines = []
            }

            let allTextLines = lines + subtitleLines
            let textWidth = allTextLines.map(\.count).max() ?? 1
            let blockH = 1 + allTextLines.count

            // Target row distance from center
            let rowDist = Int(round(2.0 + (1.0 - item.relevance) * (halfHeight - 2.0)))

            // Alternate sides: even→left, odd→right
            let isLeftSide = index % 2 == 0

            // --- Compute text start column directly ---
            // Left items: left-aligned (text starts near left margin)
            // Right items: right-aligned (text ends near right margin)
            // Golden ratio spreads items across their half

            let nominalTextCol: Int
            if isLeftSide {
                // Left-aligned: text starts near left margin
                // Spread range: minCol to centerCol - textWidth - 2
                let maxStart = max(minCol, centerCol - textWidth - 2)
                let range = max(1, maxStart - minCol)
                let spread = Int((Float(index / 2) * goldenRatio)
                    .truncatingRemainder(dividingBy: Float(range)))
                nominalTextCol = minCol + spread
            } else {
                // Right-aligned: text ends near right margin
                // Spread range: centerCol + 3 to maxCol - textWidth + 1 (reversed)
                let minStart = centerCol + 3
                let maxStart = maxCol - textWidth + 1
                let range = max(1, maxStart - minStart)
                let spread = Int((Float(index / 2) * goldenRatio)
                    .truncatingRemainder(dividingBy: Float(range)))
                nominalTextCol = maxStart - spread
            }

            // Vertical bias: left→upward, right→downward
            let targetRow: Int
            if isLeftSide {
                targetRow = centerRow - rowDist
            } else {
                targetRow = centerRow + rowDist - blockH
            }

            // --- Glyph column ---
            // Skews toward item's side but never reaches full text edge.
            // At the edge: glyph near the side-edge of text (but not at it)
            // Near center: glyph near text center

            var placed = false

            // Search: sweep rows, try small column adjustments (±5) from nominal
            for rowOffset in 0..<areaRows {
                guard !placed else { break }

                let tryRows: [Int]
                if rowOffset == 0 {
                    tryRows = [targetRow]
                } else if isLeftSide {
                    tryRows = [targetRow - rowOffset, targetRow + rowOffset]
                } else {
                    tryRows = [targetRow + rowOffset, targetRow - rowOffset]
                }

                for tryRow in tryRows {
                    guard !placed else { break }
                    guard tryRow >= minRow, tryRow + blockH - 1 <= maxRow else { continue }

                    // Try nominal column first, then small adjustments
                    for colAdj in 0...8 {
                        guard !placed else { break }
                        let adjCols: [Int] = colAdj == 0 ? [0] : [colAdj, -colAdj]

                        for adj in adjCols {
                            guard !placed else { break }
                            let textCol = max(minCol, min(maxCol - textWidth + 1, nominalTextCol + adj))

                            let glyphCol = computeGlyphCol(
                                textCol: textCol, textWidth: textWidth,
                                isLeftSide: isLeftSide,
                                centerCol: centerCol, minCol: minCol, maxCol: maxCol
                            )

                            let blockLeft = min(glyphCol, textCol)
                            let blockRight = max(glyphCol, textCol + textWidth - 1)
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
                                col: glyphCol,
                                state: CellState(character: item.glyph, color: .bold, bold: false)
                            )

                            for (lineIdx, line) in allTextLines.enumerated() {
                                let r = tryRow + 1 + lineIdx
                                guard r <= maxRow else { break }
                                // Right-side items: right-justify each line within textWidth
                                let lineStart = isLeftSide
                                    ? textCol
                                    : textCol + (textWidth - line.count)
                                for (charIdx, ch) in line.enumerated() {
                                    let c = lineStart + charIdx
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
                            placements.append(PlacedItem(
                                index: originalIndex,
                                row: startRow + tryRow,
                                col: blockLeft,
                                width: blockW,
                                height: blockH
                            ))
                            placed = true
                        }
                    }
                }
            }
        }

        return placements
    }

    // MARK: - Glyph Alignment

    /// Glyph skews toward the item's side but never reaches the text edge.
    /// Left items: glyph shifts left from text center (toward text start)
    /// Right items: glyph shifts right from text center (toward text end)
    /// Near center: glyph stays at text center
    private func computeGlyphCol(
        textCol: Int, textWidth: Int,
        isLeftSide: Bool,
        centerCol: Int, minCol: Int, maxCol: Int
    ) -> Int {
        let textCenter = textCol + textWidth / 2
        let halfSpan = Float(centerCol - minCol)
        guard halfSpan > 0, textWidth > 2 else { return textCenter }

        // How far from center (0 = at center, 1 = at edge)
        let edgeFactor = min(1.0, abs(Float(textCenter - centerCol)) / halfSpan)

        // Max shift: never reach the text edge (stop 1 col short)
        let maxShift = max(1, textWidth / 2 - 1)
        let shift = Int(round(edgeFactor * 0.7 * Float(maxShift)))

        if isLeftSide {
            // Shift glyph left (toward text start)
            return max(textCol + 1, textCenter - shift)
        } else {
            // Shift glyph right (toward text end)
            return min(textCol + textWidth - 2, textCenter + shift)
        }
    }
}

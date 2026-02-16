import UIKit

final class CharacterGrid: UIView {

    // MARK: - State

    private(set) var rowCount: Int = 0
    private(set) var metrics: GridMetrics?
    private var cells: [[CellState]] = []       // [layer][row * cols + col]
    private var dirtyRows: [Set<Int>] = []       // per-layer dirty tracking
    private var textLayers: [[CATextLayer]] = []  // [layer][row]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.masksToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let newMetrics = GridMetrics(screenWidth: bounds.width)
        let newRowCount = newMetrics.rowCount(for: bounds.height)
        if newRowCount != rowCount || metrics == nil {
            metrics = newMetrics
            rowCount = newRowCount
            rebuildGrid()
        }
        positionLayers()
    }

    // MARK: - Grid Lifecycle

    private func rebuildGrid() {
        // Tear down old layers
        for layerGroup in textLayers {
            for tl in layerGroup { tl.removeFromSuperlayer() }
        }

        let cols = GridMetrics.columns
        let totalCells = rowCount * cols

        cells = GridLayer.allCases.map { _ in
            [CellState](repeating: .empty, count: totalCells)
        }
        dirtyRows = GridLayer.allCases.map { _ in Set<Int>() }

        textLayers = GridLayer.allCases.map { gridLayer in
            (0..<rowCount).map { _ in
                let tl = CATextLayer()
                tl.contentsScale = traitCollection.displayScale
                tl.backgroundColor = UIColor.clear.cgColor
                tl.isWrapped = false
                tl.truncationMode = .none
                tl.zPosition = gridLayer.zPosition
                tl.allowsFontSubpixelQuantization = true
                layer.addSublayer(tl)
                return tl
            }
        }

        // Mark all rows dirty
        for i in GridLayer.allCases.indices {
            dirtyRows[i] = Set(0..<rowCount)
        }
    }

    private func positionLayers() {
        guard let metrics else { return }
        let x = GridMetrics.sideMargin
        let width = bounds.width - 2 * GridMetrics.sideMargin

        for layerGroup in textLayers {
            for (row, tl) in layerGroup.enumerated() {
                let y = GridMetrics.topPadding + CGFloat(row) * metrics.lineHeight
                tl.frame = CGRect(x: x, y: y, width: width, height: metrics.lineHeight)
            }
        }
    }

    // MARK: - Mutation API

    func setCell(layer: GridLayer, row: Int, col: Int, state: CellState) {
        let idx = row * GridMetrics.columns + col
        guard idx < cells[layer.rawValue].count else { return }
        cells[layer.rawValue][idx] = state
        dirtyRows[layer.rawValue].insert(row)
    }

    func setRow(layer: GridLayer, row: Int, states: [CellState]) {
        let cols = GridMetrics.columns
        for col in 0..<min(cols, states.count) {
            cells[layer.rawValue][row * cols + col] = states[col]
        }
        dirtyRows[layer.rawValue].insert(row)
    }

    func clearLayer(_ layer: GridLayer) {
        let count = cells[layer.rawValue].count
        cells[layer.rawValue] = [CellState](repeating: .empty, count: count)
        dirtyRows[layer.rawValue] = Set(0..<rowCount)
    }

    func clearRow(layer: GridLayer, row: Int) {
        let cols = GridMetrics.columns
        for col in 0..<cols {
            cells[layer.rawValue][row * cols + col] = .empty
        }
        dirtyRows[layer.rawValue].insert(row)
    }

    // MARK: - Coordinate Mapping

    func rectForCell(row: Int, col: Int) -> CGRect {
        guard let metrics else { return .zero }
        let cols = GridMetrics.columns
        let gridWidth = bounds.width - 2 * GridMetrics.sideMargin
        let cellWidth = gridWidth / CGFloat(cols)

        let x = GridMetrics.sideMargin + CGFloat(col) * cellWidth
        let y = GridMetrics.topPadding + CGFloat(row) * metrics.lineHeight
        return CGRect(x: x, y: y, width: cellWidth, height: metrics.lineHeight)
    }

    func rectForRegion(row: Int, col: Int, rowSpan: Int, colSpan: Int) -> CGRect {
        let topLeft = rectForCell(row: row, col: col)
        let bottomRight = rectForCell(row: row + rowSpan - 1, col: col + colSpan - 1)
        return topLeft.union(bottomRight)
    }

    // MARK: - Render

    func render() {
        guard let metrics else { return }
        let cols = GridMetrics.columns
        let kern = metrics.kern

        for layerIdx in GridLayer.allCases.indices {
            for row in dirtyRows[layerIdx] {
                guard row < textLayers[layerIdx].count else { continue }
                let tl = textLayers[layerIdx][row]
                let rowStart = row * cols

                let attributed = NSMutableAttributedString()
                for col in 0..<cols {
                    let cell = cells[layerIdx][rowStart + col]
                    let font: UIFont
                    if cell.small {
                        font = cell.bold ? metrics.smallBoldFont : metrics.smallFont
                    } else {
                        font = cell.bold ? metrics.boldFont : metrics.font
                    }
                    let cellKern = cell.small ? metrics.smallKern : kern
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: cell.color.uiColor,
                        .kern: col < cols - 1 ? cellKern : 0
                    ]
                    attributed.append(NSAttributedString(string: String(cell.character), attributes: attrs))
                }

                tl.string = attributed
            }
            dirtyRows[layerIdx].removeAll()
        }
    }
}

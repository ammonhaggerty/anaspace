import SwiftUI

// MARK: - Grid Alignment Modifier

extension View {
    /// Position a view at a specific grid cell, aligned to the top-leading corner of the cell.
    func gridAligned(row: Int, col: Int, metrics: GridMetrics) -> some View {
        self.offset(
            x: GridMetrics.sideMargin + CGFloat(col) * metrics.cellWidth,
            y: GridMetrics.topPadding + CGFloat(row) * metrics.lineHeight
        )
    }
}

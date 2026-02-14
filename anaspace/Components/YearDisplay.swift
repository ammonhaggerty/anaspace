import SwiftUI

struct YearDisplay: View {
    let year: Int
    let metrics: GridMetrics
    var onTap: () -> Void = {}

    // Each digit occupies a 4-col x 3-row grid block
    private static let digitCols = 4
    private static let digitRows = 3

    // Layout: 2 digits per row, 2 rows of digits, button below
    private var digits: [Int] {
        let clamped = max(0, min(9999, year))
        return [
            clamped / 1000,
            (clamped / 100) % 10,
            (clamped / 10) % 10,
            clamped % 10,
        ]
    }

    private var digitWidth: CGFloat {
        CGFloat(Self.digitCols) * metrics.cellWidth
    }

    private var digitHeight: CGFloat {
        CGFloat(Self.digitRows) * metrics.lineHeight
    }

    private var pairWidth: CGFloat {
        2 * digitWidth
    }

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                digitImage(digits[0])
                digitImage(digits[1])
            }
            HStack(spacing: 0) {
                digitImage(digits[2])
                digitImage(digits[3])
            }
            Color.clear
                .frame(width: pairWidth, height: metrics.lineHeight)
            GridButton(label: "YEAR", icon: "\u{2713}", metrics: metrics)
        }
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    isPressed = false
                    onTap()
                }
        )
    }

    private func digitImage(_ digit: Int) -> some View {
        Image("year\(digit)")
            .resizable()
            .scaledToFit()
            .frame(width: digitWidth, height: digitHeight)
    }
}

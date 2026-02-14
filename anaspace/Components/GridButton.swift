import SwiftUI

struct GridButton: View {
    let label: String
    let icon: String?
    let metrics: GridMetrics
    var onTap: () -> Void = {}

    // Figma ratio: button font 12px / grid font 15.52px
    private static let fontSizeRatio: CGFloat = 12.0 / 15.52
    // Figma ratio: 4px bevel / 22.3px cell height
    private static let bevelRatio: CGFloat = 4.0 / 22.3

    init(label: String, icon: String? = nil, metrics: GridMetrics, onTap: @escaping () -> Void = {}) {
        self.label = label
        self.icon = icon
        self.metrics = metrics
        self.onTap = onTap
    }

    private var displayText: String {
        if let icon { return icon + " " + label }
        return label
    }

    private var buttonFontSize: CGFloat {
        metrics.fontSize * Self.fontSizeRatio
    }

    private var buttonFont: UIFont {
        UIFont(name: FontName.bold, size: buttonFontSize)
            ?? .monospacedSystemFont(ofSize: buttonFontSize, weight: .bold)
    }

    private var buttonWidth: CGFloat {
        // Text characters + 2 end-cap cells
        CGFloat(displayText.count + 2) * metrics.cellWidth
    }

    private var buttonHeight: CGFloat {
        metrics.lineHeight
    }

    private var bevel: CGFloat {
        buttonHeight * Self.bevelRatio
    }

    @State private var isPressed = false

    var body: some View {
        BeveledShape(bevel: bevel)
            .fill(GridColor.bold.uiColor.swiftUI)
            .frame(width: buttonWidth, height: buttonHeight)
            .overlay {
                HStack(spacing: 0) {
                    Color.clear.frame(width: metrics.cellWidth)
                    ForEach(Array(displayText.uppercased().enumerated()), id: \.offset) { _, ch in
                        Text(String(ch))
                            .font(Font(buttonFont))
                            .foregroundStyle(GridColor.tint.uiColor.swiftUI)
                            .frame(width: metrics.cellWidth, height: buttonHeight)
                    }
                    Color.clear.frame(width: metrics.cellWidth)
                }
            }
            .scaleEffect(isPressed ? 0.96 : 1.0)
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
}

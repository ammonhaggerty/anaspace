import SwiftUI

@main
struct AnaspaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var controller = GridController()
    @State private var hasPopulated = false

    var body: some View {
        ZStack {
            GridColor.background.uiColor.swiftUI
                .ignoresSafeArea()

            VStack(spacing: 0) {
                CharacterGridView(controller: controller) { grid in
                    guard !hasPopulated else { return }
                    hasPopulated = true
                    populateGrid(grid)
                }

                BottomNavBar(
                    isObserving: controller.isObserving,
                    onObserveTap: {
                        controller.triggerObserve { grid in
                            populateGrid(grid)
                        }
                    }
                )
                    .frame(height: GridMetrics.bottomFooter)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden()
    }

    private func populateGrid(_ grid: CharacterGrid) {
        fillStructureLayer(grid)
        fillContentLayer(grid)
        grid.render()
    }

    // MARK: - Structure Layer

    private func fillStructureLayer(_ grid: CharacterGrid) {
        // Uniform light-shade grid creating a subtle fabric texture
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

    // MARK: - Content Layer

    private func fillContentLayer(_ grid: CharacterGrid) {
        let text = "READY TO OBSERVE"
        let cols = GridMetrics.columns
        let centerRow = grid.rowCount / 2

        // Red dot: centered before text
        let totalWidth = 2 + text.count  // dot + space + text
        let startCol = max(0, (cols - totalWidth) / 2)

        // Dot character
        grid.setCell(
            layer: .content, row: centerRow, col: startCol,
            state: CellState(character: "\u{25CF}", color: .focus, bold: true)
        )

        // Text after dot + space
        for (i, ch) in text.enumerated() {
            grid.setCell(
                layer: .content, row: centerRow, col: startCol + 2 + i,
                state: CellState(character: ch, color: .bold, bold: false)
            )
        }
    }
}

// MARK: - Bottom Nav Bar

struct BottomNavBar: View {
    var isObserving: Bool = false
    var onObserveTap: () -> Void = {}

    private let navDark = GridColor.bold.uiColor.swiftUI
    private let bg = GridColor.background.uiColor.swiftUI
    private let red = GridColor.focus.uiColor.swiftUI

    var body: some View {
        HStack {
            // History button
            NavButton(iconName: "icon-history", fg: bg, bg: navDark)

            Spacer()

            // Observe button
            ObserveButton(
                isObserving: isObserving,
                navDark: navDark,
                bg: bg,
                red: red,
                onTap: onObserveTap
            )

            Spacer()

            // Options button
            NavButton(iconName: "icon-options", fg: bg, bg: navDark)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }
}

// MARK: - Nav Button with Hit State

private struct NavButton: View {
    let iconName: String
    let fg: Color
    let bg: Color

    @State private var isPressed = false

    var body: some View {
        Circle()
            .fill(bg)
            .frame(width: 44, height: 44)
            .overlay(
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(fg)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - Observe Button with Pulse

private struct ObserveButton: View {
    let isObserving: Bool
    let navDark: Color
    let bg: Color
    let red: Color
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(navDark)
            .frame(width: 62, height: 62)
            .overlay(
                Circle()
                    .fill(isObserving ? red : bg)
                    .frame(width: 26, height: 26)
                    .scaleEffect(isObserving ? pulseScale : 1.0)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .onChange(of: isObserving) { _, active in
                if active {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.1
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        pulseScale = 1.0
                    }
                }
            }
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

// MARK: - Color Bridge

extension UIColor {
    var swiftUI: Color { Color(uiColor: self) }
}

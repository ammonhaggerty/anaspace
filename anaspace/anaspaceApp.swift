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

                BottomNavBar(onObserveTap: {
                    controller.triggerObserve { grid in
                        populateGrid(grid)
                    }
                })
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
    var onObserveTap: () -> Void = {}

    private let navDark = GridColor.bold.uiColor.swiftUI
    private let bg = GridColor.background.uiColor.swiftUI

    var body: some View {
        HStack {
            // History button
            Circle()
                .fill(navDark)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\u{21BB}")
                        .font(.system(size: 18))
                        .foregroundStyle(bg)
                )

            Spacer()

            // Observe button (larger, with crescent)
            Circle()
                .fill(navDark)
                .frame(width: 62, height: 62)
                .overlay(
                    Circle()
                        .fill(bg)
                        .frame(width: 26, height: 26)
                        .offset(x: 8, y: -8)
                        .mask(
                            Circle()
                                .frame(width: 62, height: 62)
                        )
                )
                .onTapGesture {
                    onObserveTap()
                }

            Spacer()

            // Options button
            Circle()
                .fill(navDark)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\u{2630}")
                        .font(.system(size: 16))
                        .foregroundStyle(bg)
                )
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }
}

// MARK: - Color Bridge

extension UIColor {
    var swiftUI: Color { Color(uiColor: self) }
}

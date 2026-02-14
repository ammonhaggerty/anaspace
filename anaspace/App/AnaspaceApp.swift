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
    @State private var appState = AppState()
    @State private var navManager = NavigationManager()
    @State private var controller = GridController()
    @State private var hasPopulated = false

    // Page renderers
    @State private var renderers: [Page: any PageRenderer] = [
        .home: HomePageRenderer(),
        .history: HistoryPageRenderer(),
        .options: OptionsPageRenderer(),
    ]

    private var currentRenderer: any PageRenderer {
        renderers[navManager.currentPage] ?? HomePageRenderer()
    }

    var body: some View {
        ZStack {
            GridColor.background.uiColor.swiftUI
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    // Component layer — under the grid text
                    if let metrics = controller.metrics {
                        componentLayer(metrics: metrics)
                    }

                    // Grid — transparent background, text layers on top
                    CharacterGridView(controller: controller) { grid in
                        guard !hasPopulated else { return }
                        hasPopulated = true
                        controller.metrics = grid.metrics
                        populateGrid(grid)
                    }
                }

                BottomNavBar(
                    isObserving: controller.isObserving,
                    onObserveTap: {
                        controller.triggerObserve { grid in
                            populateGrid(grid)
                        }
                    },
                    onHistoryTap: {
                        navigateTo(.history)
                    },
                    onOptionsTap: {
                        navigateTo(.options)
                    }
                )
                    .frame(height: GridMetrics.bottomFooter)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden()
    }

    // MARK: - Component Layer

    @ViewBuilder
    private func componentLayer(metrics: GridMetrics) -> some View {
        let cols = GridMetrics.columns

        // "✓ LOCATION" = 12 chars + 2 end caps = 14 cells
        // "✓ YEAR" = 6 chars + 2 end caps = 8 cells
        // YEAR button right-aligned: col = 33 - 8 = 25
        GridButton(label: "LOCATION", icon: "\u{2713}", metrics: metrics)
            .gridAligned(row: 9, col: 0, metrics: metrics)

        GridButton(label: "YEAR", icon: "\u{2713}", metrics: metrics)
            .gridAligned(row: 9, col: cols - 8, metrics: metrics)
    }

    // MARK: - Grid Population

    private func populateGrid(_ grid: CharacterGrid) {
        currentRenderer.renderStructure(into: grid)
        currentRenderer.renderContent(into: grid)
        grid.render()
    }

    private func navigateTo(_ page: Page) {
        guard let targetRenderer = renderers[page] else { return }
        navManager.navigate(to: page, using: controller, renderer: targetRenderer)
    }
}

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

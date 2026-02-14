import SwiftUI
import CoreLocation

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
    @State private var showMapSelection = false
    @State private var selectedYear: Int = 1978
    @State private var showYearPicker = false
    @State private var selectedCoordinate = CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2712)
    @State private var serviceManager = ServiceManager()

    // Page renderers
    @State private var renderers: [Page: any PageRenderer] = [
        .home: HomePageRenderer(),
        .history: HistoryPageRenderer(),
        .options: OptionsPageRenderer(),
    ]

    private var currentRenderer: any PageRenderer {
        renderers[navManager.currentPage] ?? HomePageRenderer()
    }

    private var homeRenderer: HomePageRenderer? {
        renderers[.home] as? HomePageRenderer
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
                .overlay(alignment: .topLeading) {
                    // Tap overlay above grid for map widget (rows 0-9)
                    if navManager.currentPage == .home, let metrics = controller.metrics {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(24) * metrics.cellWidth,
                                height: CGFloat(10) * metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin,
                                y: GridMetrics.topPadding
                            )
                            .onTapGesture { showMapSelection = true }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlay for year display (rows 1-8, right-aligned 8 cols)
                    if navManager.currentPage == .home, let metrics = controller.metrics {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(8) * metrics.cellWidth,
                                height: CGFloat(8) * metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin + CGFloat(GridMetrics.columns - 8) * metrics.cellWidth,
                                y: GridMetrics.topPadding + metrics.lineHeight
                            )
                            .onTapGesture { showYearPicker = true }
                    }
                }

                Group {
                    if navManager.currentPage == .home {
                        BottomNavBar(
                            isObserving: controller.isObserving,
                            onObserveTap: {
                                if serviceManager.isObserving {
                                    serviceManager.endObservation()
                                } else {
                                    Task {
                                        await serviceManager.beginObservation()
                                    }
                                    controller.triggerObserve { grid in
                                        populateGrid(grid)
                                    }
                                }
                            },
                            onHistoryTap: {
                                navigateTo(.history)
                            },
                            onOptionsTap: {
                                navigateTo(.options)
                            },
                            onHoldStart: {
                                Task {
                                    await serviceManager.beginObservation()
                                    serviceManager.setHoldMode()
                                }
                                controller.triggerObserve { grid in
                                    populateGrid(grid)
                                }
                            },
                            onHoldEnd: {
                                serviceManager.endObservation()
                            }
                        )
                    } else {
                        HStack {
                            NavButton(
                                iconName: "arrow-back",
                                fg: GridColor.background.uiColor.swiftUI,
                                bg: GridColor.bold.uiColor.swiftUI
                            ) {
                                navigateTo(.home)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    }
                }
                .frame(height: GridMetrics.bottomFooter)
            }
            .ignoresSafeArea()
        }
        .statusBarHidden()
        .task {
            await serviceManager.refreshPermissions()
        }
        .fullScreenCover(isPresented: $showMapSelection) {
            MapSelectionView(
                initialCoordinate: selectedCoordinate,
                onLocationSelected: { coordinate in
                    selectedCoordinate = coordinate
                    showMapSelection = false
                    reverseGeocode(coordinate)
                    refreshGrid()
                },
                onDismiss: {
                    showMapSelection = false
                }
            )
        }
        .fullScreenCover(isPresented: $showYearPicker) {
            YearPickerView(
                initialYear: selectedYear,
                onYearSelected: { year in
                    selectedYear = year
                    showYearPicker = false
                    refreshGrid()
                },
                onDismiss: { showYearPicker = false }
            )
        }
    }

    // MARK: - Component Layer

    @ViewBuilder
    private func componentLayer(metrics: GridMetrics) -> some View {
        let cols = GridMetrics.columns

        if navManager.currentPage == .home {
            // Map widget: map (rows 0-6) + button (row 8) + label (row 9)
            let mapCols = 24
            let mapRows = 7
            let mapWidth = CGFloat(mapCols) * metrics.cellWidth
            let mapHeight = CGFloat(mapRows) * metrics.lineHeight
            let glyphMask = GlyphMask.render(cols: mapCols, rows: mapRows, metrics: metrics)

            MapDisplay(
                metrics: metrics,
                coordinate: selectedCoordinate,
                zoom: 8
            )
            .frame(width: mapWidth, height: mapHeight)
            .mask(Image(uiImage: glyphMask).resizable())
            .blendMode(.multiply)
            .gridAligned(row: 0, col: 0, metrics: metrics)

            GridButton(label: "LOCATION", icon: "\u{2713}", metrics: metrics)
                .gridAligned(row: 8, col: 0, metrics: metrics)

            // Year display: 2x2 digits (8 cols wide, 6 rows tall) + 1 gap + button
            // Right-aligned: col = 33 - 8 = 25, starting at row 1
            YearDisplay(year: selectedYear, metrics: metrics, onTap: { showYearPicker = true })
                .gridAligned(row: 1, col: cols - 8, metrics: metrics)
        }

        if navManager.currentPage == .options {
            if let optionsRenderer = renderers[.options] as? OptionsPageRenderer {
                let rows = optionsRenderer.settingsRows
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    let labels = ["LOG OUT", "UNLINK", "DOWNLOAD DATA"]
                    if index < labels.count {
                        GridButton(label: labels[index], metrics: metrics)
                            .gridAligned(row: row, col: 1, metrics: metrics)
                    }
                }
            }
        }
    }

    // MARK: - Grid Population

    private func populateGrid(_ grid: CharacterGrid) {
        currentRenderer.renderStructure(into: grid)
        currentRenderer.renderContent(into: grid)
        grid.render()
    }

    private func refreshGrid() {
        guard let grid = controller.grid else { return }
        grid.clearLayer(.content)
        currentRenderer.renderContent(into: grid)
        grid.render()
    }

    private func navigateTo(_ page: Page) {
        guard let targetRenderer = renderers[page] else { return }
        navManager.navigate(to: page, using: controller, renderer: targetRenderer)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        Task {
            guard let result = await serviceManager.location.reverseGeocode(coordinate) else { return }
            homeRenderer?.locationLabel = LocationService.displayLabel(for: result)
            refreshGrid()
        }
    }
}

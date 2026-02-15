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
    @State private var onboardingRenderer = OnboardingRenderer()

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
                        if appState.hasCompletedOnboarding {
                            componentLayer(metrics: metrics)
                        } else {
                            onboardingComponentLayer(metrics: metrics)
                        }
                    }

                    // Grid — transparent background, text layers on top
                    CharacterGridView(controller: controller) { grid in
                        guard !hasPopulated else { return }
                        hasPopulated = true
                        controller.metrics = grid.metrics
                        populateGrid(grid)
                    }

                }
                .overlay {
                    // Full-screen tap for onboarding
                    if !appState.hasCompletedOnboarding {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleOnboardingTap()
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlay above grid for map widget (rows 0-9)
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .home,
                       homeRenderer?.hasObservations == true,
                       let metrics = controller.metrics {
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
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .home,
                       homeRenderer?.hasObservations == true,
                       let metrics = controller.metrics {
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
                    if !appState.hasCompletedOnboarding {
                        Spacer()
                    } else if navManager.currentPage == .home {
                        BottomNavBar(
                            isObserving: controller.isObserving,
                            onObserveTap: {
                                guard serviceManager.progress.phase == .idle else { return }
                                Task { await serviceManager.beginCapture() }
                                controller.enterCapture(
                                    mode: .observing,
                                    progress: serviceManager.progress,
                                    audioService: serviceManager.audio,
                                    onWipeOutComplete: {}
                                )
                            },
                            onHistoryTap: {
                                navigateTo(.history)
                            },
                            onOptionsTap: {
                                navigateTo(.options)
                            },
                            onHoldStart: {
                                Task { await serviceManager.upgradeToHold() }
                                controller.upgradeCaptureToHold()
                            },
                            onHoldEnd: {
                                serviceManager.endCapture()
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
            onboardingRenderer.permissions = serviceManager.permissions
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Re-check permissions when returning from Settings
            if !appState.hasCompletedOnboarding && onboardingRenderer.isMicDenied {
                Task {
                    await serviceManager.refreshPermissions()
                    if serviceManager.permissions.microphone == .granted {
                        advanceOnboarding()
                    } else {
                        refreshOnboardingGrid()
                    }
                }
            }
        }
        .onChange(of: serviceManager.progress.latestResult?.narrative) { _, _ in
            handleResultUpdate()
        }
        .onChange(of: serviceManager.progress.phase) { _, newPhase in
            if newPhase == .resolved {
                handleResultUpdate()
                controller.exitCapture { grid in
                    populateGrid(grid)
                }
            }
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
        if !controller.isCapturing {
            let cols = GridMetrics.columns

            if navManager.currentPage == .home, homeRenderer?.hasObservations == true {
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
    }

    // MARK: - Grid Population

    private func populateGrid(_ grid: CharacterGrid) {
        if appState.hasCompletedOnboarding {
            currentRenderer.renderStructure(into: grid)
            currentRenderer.renderContent(into: grid)
        } else {
            // Content first — computes hiddenStructureRows for buttons
            onboardingRenderer.renderContent(into: grid)
            onboardingRenderer.renderStructure(into: grid)
        }
        grid.render()
    }

    private func refreshGrid() {
        guard let grid = controller.grid else { return }
        grid.clearLayer(.content)
        grid.clearLayer(.structure)
        currentRenderer.renderStructure(into: grid)
        currentRenderer.renderContent(into: grid)
        grid.render()
    }

    private func handleResultUpdate() {
        guard let result = serviceManager.progress.latestResult else { return }
        guard let home = homeRenderer else { return }

        home.hasObservations = true
        home.graphSubject = GraphSubject(label: result.subject.uppercased())

        // Build graph items from connections
        home.graphItems = result.connections.map { conn in
            GraphItem(glyph: "\u{25A0}", label: conn.name, relevance: Float(conn.relevance))
        }

        selectedYear = result.year

        // Update location from progress
        if let loc = serviceManager.progress.location {
            selectedCoordinate = loc.coordinate
            homeRenderer?.locationLabel = LocationService.displayLabel(for: loc)
        }

        refreshGrid()
    }

    private func navigateTo(_ page: Page) {
        guard let targetRenderer = renderers[page] else { return }
        navManager.navigate(to: page, using: controller, renderer: targetRenderer)
    }

    // MARK: - Onboarding Component Layer

    @ViewBuilder
    private func onboardingComponentLayer(metrics: GridMetrics) -> some View {
        let step = onboardingRenderer.currentStep

        // CONTINUE / BEGIN button (shown on all steps except mic-denied)
        if onboardingRenderer.continueButtonRow > 0 {
            let label = step == .tips ? "BEGIN" : "CONTINUE"
            GridButton(label: label, metrics: metrics) {
                handleOnboardingTap()
            }
            .gridAligned(row: onboardingRenderer.continueButtonRow, col: centeredButtonCol(label), metrics: metrics)
        }

        // OPEN SETTINGS button (mic denied only)
        if onboardingRenderer.settingsButtonRow > 0 {
            GridButton(label: "OPEN SETTINGS", metrics: metrics) {
                openSettings()
            }
            .gridAligned(row: onboardingRenderer.settingsButtonRow, col: centeredButtonCol("OPEN SETTINGS"), metrics: metrics)
        }
    }

    /// Center a GridButton (label + 2 end-cap cols) within the 33-col grid.
    private func centeredButtonCol(_ label: String) -> Int {
        let buttonCols = label.count + 2
        return max(0, (GridMetrics.columns - buttonCols) / 2)
    }

    // MARK: - Onboarding Navigation

    private func handleOnboardingTap() {
        switch onboardingRenderer.currentStep {
        case .welcome:
            advanceOnboarding()
        case .microphone:
            if onboardingRenderer.isMicDenied { return }
            Task {
                await serviceManager.permissions.requestMicrophone()
                if serviceManager.permissions.microphone == .granted {
                    advanceOnboarding()
                } else {
                    refreshOnboardingGrid()
                }
            }
        case .location:
            Task {
                await serviceManager.permissions.requestLocation()
                advanceOnboarding()
            }
        case .speech:
            Task {
                await serviceManager.permissions.requestSpeechRecognition()
                advanceOnboarding()
            }
        case .tips:
            completeOnboarding()
        }
    }

    private func advanceOnboarding() {
        guard let grid = controller.grid else { return }
        controller.cascade.run(on: grid) { [self] in
            let nextStep: OnboardingStep? = switch onboardingRenderer.currentStep {
            case .welcome: .microphone
            case .microphone: .location
            case .location: .speech
            case .speech: .tips
            case .tips: nil
            }
            guard let next = nextStep else { return }
            onboardingRenderer.currentStep = next

            // Skip permission steps that are already granted
            if onboardingRenderer.shouldSkipCurrentStep {
                skipToNextStep(grid: grid)
                return
            }

            renderOnboardingStep(grid: grid)
        }
    }

    /// Recursively skip already-granted permission steps.
    private func skipToNextStep(grid: CharacterGrid) {
        let nextStep: OnboardingStep? = switch onboardingRenderer.currentStep {
        case .welcome: .microphone
        case .microphone: .location
        case .location: .speech
        case .speech: .tips
        case .tips: nil
        }
        guard let next = nextStep else {
            // All permissions already granted — go to tips
            onboardingRenderer.currentStep = .tips
            renderOnboardingStep(grid: grid)
            return
        }
        onboardingRenderer.currentStep = next
        if onboardingRenderer.shouldSkipCurrentStep {
            skipToNextStep(grid: grid)
        } else {
            renderOnboardingStep(grid: grid)
        }
    }

    private func renderOnboardingStep(grid: CharacterGrid) {
        grid.clearLayer(.structure)
        grid.clearLayer(.content)
        onboardingRenderer.renderContent(into: grid)
        onboardingRenderer.renderStructure(into: grid)
        grid.render()
    }

    private func completeOnboarding() {
        guard let grid = controller.grid else { return }
        controller.cascade.run(on: grid) { [self] in
            appState.hasCompletedOnboarding = true
            grid.clearLayer(.structure)
            grid.clearLayer(.content)
            populateGrid(grid)
        }
    }

    private func refreshOnboardingGrid() {
        guard let grid = controller.grid else { return }
        renderOnboardingStep(grid: grid)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        Task {
            guard let result = await serviceManager.location.reverseGeocode(coordinate) else { return }
            homeRenderer?.locationLabel = LocationService.displayLabel(for: result)
            refreshGrid()
        }
    }
}

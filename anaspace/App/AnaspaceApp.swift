import SwiftUI
import CoreLocation

struct ContextChangeSnapshot {
    let hasObservations: Bool
    let graphSubject: GraphSubject
    let graphItems: [GraphItem]
    let connections: [CultureConnection]
    let bio: String
    let birthInfo: String
    let locationLabel: String
    let selectedYear: Int
    let selectedCoordinate: CLLocationCoordinate2D
    let activeHistoryEntryId: UUID?
}

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
    @State private var isOnboardingTransitioning = false
    @State private var historyStore = HistoryStore()
    @State private var activeHistoryEntryId: UUID?
    @State private var usedCircaYears: Set<Int> = []
    @State private var contextChangeSnapshot: ContextChangeSnapshot?
    @State private var captureExitInitiated = false

    #if DEBUG
    @State private var harnessReport: String?
    @State private var isHarnessRunning = false
    #endif

    // Page renderers
    @State private var renderers: [Page: any PageRenderer] = [
        .home: HomePageRenderer(),
        .history: HistoryPageRenderer(),
        .options: OptionsPageRenderer(),
        .info: InfoPageRenderer(),
    ]

    private var currentRenderer: any PageRenderer {
        renderers[navManager.currentPage] ?? HomePageRenderer()
    }

    private var homeRenderer: HomePageRenderer? {
        renderers[.home] as? HomePageRenderer
    }

    private var infoRenderer: InfoPageRenderer? {
        renderers[.info] as? InfoPageRenderer
    }

    private var historyRenderer: HistoryPageRenderer? {
        renderers[.history] as? HistoryPageRenderer
    }

    private var footerState: FooterState {
        guard appState.hasCompletedOnboarding else { return .hidden }
        guard navManager.currentPage == .home else { return .subpage }
        if controller.isCapturing {
            if controller.isContextChangeCapture { return .contextChange }
            if controller.isEvaluating { return .hidden }
            return .homeObserving
        }
        return .homeIdle
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

                    // Transition cover — blocks components from showing through grid kern gaps
                    if navManager.isTransitioning || isOnboardingTransitioning {
                        GridColor.background.uiColor.swiftUI
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
                                Task {
                                    // Show pressed state
                                    if let grid = controller.grid {
                                        onboardingRenderer.renderButtonPressed(into: grid)
                                        grid.render()
                                        try? await Task.sleep(for: .milliseconds(300))
                                    }
                                    handleOnboardingTap()
                                }
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
                .overlay(alignment: .topLeading) {
                    // Tap overlay for subject label in radial graph center
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .home,
                       homeRenderer?.hasObservations == true,
                       let metrics = controller.metrics {
                        let graphStartRow = 12
                        let graphEndRow = (controller.grid?.rowCount ?? 40) - 2
                        let centerRow = graphStartRow + (graphEndRow - graphStartRow) / 2 - 1
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(16) * metrics.cellWidth,
                                height: CGFloat(3) * metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin + CGFloat((GridMetrics.columns - 16) / 2) * metrics.cellWidth,
                                y: GridMetrics.topPadding + CGFloat(centerRow - 1) * metrics.lineHeight
                            )
                            .onTapGesture {
                                Task {
                                    if let grid = controller.grid, let home = homeRenderer {
                                        home.renderSubjectPressed(into: grid)
                                        grid.render()
                                        try? await Task.sleep(for: .milliseconds(300))
                                    }
                                    navigateToInfo()
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlays for placed entities in radial graph
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .home,
                       let home = homeRenderer,
                       home.hasObservations,
                       let metrics = controller.metrics {
                        ZStack(alignment: .topLeading) {
                            ForEach(home.placements, id: \.index) { placement in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(
                                        width: CGFloat(placement.textWidth + 2) * metrics.cellWidth,
                                        height: CGFloat(placement.textHeight + 2) * metrics.lineHeight
                                    )
                                    .offset(
                                        x: GridMetrics.sideMargin + CGFloat(max(0, placement.textCol - 1)) * metrics.cellWidth,
                                        y: GridMetrics.topPadding + CGFloat(max(0, placement.textRow - 1)) * metrics.lineHeight
                                    )
                                    .onTapGesture {
                                        guard placement.index < home.connections.count else { return }
                                        navigateToEntityInfo(home.connections[placement.index])
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlays for history page
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .history,
                       let history = historyRenderer,
                       let metrics = controller.metrics {
                        ZStack(alignment: .topLeading) {
                            // Reset button (3-row bracket area)
                            if history.resetButtonRow >= 0 {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(
                                        width: CGFloat(GridMetrics.columns) * metrics.cellWidth,
                                        height: CGFloat(3) * metrics.lineHeight
                                    )
                                    .offset(
                                        x: GridMetrics.sideMargin,
                                        y: GridMetrics.topPadding + CGFloat(history.resetButtonRow) * metrics.lineHeight
                                    )
                                    .onTapGesture {
                                        Task {
                                            if let grid = controller.grid, let history = historyRenderer {
                                                history.renderResetButtonPressed(into: grid)
                                                grid.render()
                                                try? await Task.sleep(for: .milliseconds(300))
                                            }
                                            resetToObservePage()
                                        }
                                    }
                            }
                            // History entries
                            ForEach(Array(history.entryRows.enumerated()), id: \.offset) { index, row in
                                if index < history.entries.count {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .frame(
                                            width: CGFloat(GridMetrics.columns) * metrics.cellWidth,
                                            height: metrics.lineHeight
                                        )
                                        .offset(
                                            x: GridMetrics.sideMargin,
                                            y: GridMetrics.topPadding + CGFloat(row) * metrics.lineHeight
                                        )
                                        .onTapGesture {
                                            restoreFromHistory(history.entries[index])
                                        }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlays for idea cards on Ready to Observe screen
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .home,
                       homeRenderer?.hasObservations == false,
                       let home = homeRenderer,
                       !home.ideaCardRegions.isEmpty,
                       let metrics = controller.metrics {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(home.ideaCardRegions.enumerated()), id: \.offset) { index, region in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(
                                        width: CGFloat(region.width) * metrics.cellWidth,
                                        height: CGFloat(region.height) * metrics.lineHeight
                                    )
                                    .offset(
                                        x: GridMetrics.sideMargin + CGFloat(region.col) * metrics.cellWidth,
                                        y: GridMetrics.topPadding + CGFloat(region.row) * metrics.lineHeight
                                    )
                                    .onTapGesture {
                                        Task {
                                            if let grid = controller.grid, let home = homeRenderer {
                                                home.renderIdeaCardPressed(index: index, into: grid)
                                                grid.render()
                                                try? await Task.sleep(for: .milliseconds(300))
                                            }
                                            handleIdeaCardTap(index: index)
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlay for GitHub link on options page
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .options,
                       let opts = renderers[.options] as? OptionsPageRenderer,
                       opts.githubLinkRow >= 0,
                       let metrics = controller.metrics {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(opts.githubLinkEndCol - opts.githubLinkStartCol + 1) * metrics.cellWidth,
                                height: metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin + CGFloat(opts.githubLinkStartCol) * metrics.cellWidth,
                                y: GridMetrics.topPadding + CGFloat(opts.githubLinkRow) * metrics.lineHeight
                            )
                            .onTapGesture {
                                if let url = URL(string: "https://github.com/ammonhaggerty/anaspace") {
                                    UIApplication.shared.open(url)
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlay for autoplay toggle on options page
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .options,
                       let opts = renderers[.options] as? OptionsPageRenderer,
                       opts.toggleRow >= 0,
                       let metrics = controller.metrics {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(GridMetrics.columns) * metrics.cellWidth,
                                height: metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin,
                                y: GridMetrics.topPadding + CGFloat(opts.toggleRow) * metrics.lineHeight
                            )
                            .onTapGesture {
                                appState.autoplayEnabled.toggle()
                                refreshGrid()
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Play/Stop button overlay for audio player
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       serviceManager.audioPlayer.state != .idle || !serviceManager.audioPlayer.queue.isEmpty,
                       let metrics = controller.metrics,
                       let grid = controller.grid {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(3) * metrics.cellWidth,
                                height: metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin + CGFloat(27) * metrics.cellWidth,
                                y: GridMetrics.topPadding + CGFloat(grid.rowCount - 1) * metrics.lineHeight
                            )
                            .onTapGesture { serviceManager.audioPlayer.togglePlayStop() }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Skip button overlay for audio player
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       serviceManager.audioPlayer.state == .playing,
                       let metrics = controller.metrics,
                       let grid = controller.grid {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: CGFloat(3) * metrics.cellWidth,
                                height: metrics.lineHeight
                            )
                            .offset(
                                x: GridMetrics.sideMargin + CGFloat(30) * metrics.cellWidth,
                                y: GridMetrics.topPadding + CGFloat(grid.rowCount - 1) * metrics.lineHeight
                            )
                            .onTapGesture { serviceManager.audioPlayer.skip() }
                    }
                }

                Group {
                    switch footerState {
                    case .hidden:
                        Spacer()
                    case .homeIdle, .homeObserving:
                        BottomNavBar(
                            isObserving: controller.isCapturing,
                            onObserveTap: {
                                guard serviceManager.progress.phase == .idle || serviceManager.progress.phase == .resolved else { return }
                                activeHistoryEntryId = nil
                                homeRenderer?.showNothingObserved = false
                                Task { await serviceManager.beginCapture() }
                                controller.enterCapture(
                                    mode: .observing,
                                    progress: serviceManager.progress,
                                    audioService: serviceManager.audio,
                                    contextYear: selectedYear,
                                    onWipeOutComplete: {}
                                )
                            },
                            onHistoryTap: {
                                historyRenderer?.entries = historyStore.entries
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
                                Task {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    serviceManager.endCapture()
                                }
                            }
                        )
                    case .contextChange:
                        HStack {
                            NavButton(
                                iconName: "cancel",
                                fg: GridColor.tint.uiColor.swiftUI,
                                bg: GridColor.bold.uiColor.swiftUI
                            ) {
                                cancelContextChange()
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    case .subpage:
                        HStack {
                            NavButton(
                                iconName: "arrow-back",
                                fg: GridColor.tint.uiColor.swiftUI,
                                bg: GridColor.bold.uiColor.swiftUI
                            ) {
                                goBack()
                            }
                            Spacer()
                            if navManager.currentPage == .info,
                               infoRenderer?.mode == .entity {
                                NavTextButton(
                                    label: "FOCUS",
                                    fg: GridColor.tint.uiColor.swiftUI,
                                    bg: GridColor.bold.uiColor.swiftUI
                                ) {
                                    makeEntitySubject()
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    }
                }
                .frame(height: GridMetrics.bottomFooter)
            }
            .ignoresSafeArea()
        }
        .task {
            historyStore.load()
            serviceManager.appState = appState
            await serviceManager.refreshPermissions()
            onboardingRenderer.permissions = serviceManager.permissions

            // Prompt optimization harness — disabled, uncomment to run:
            // #if DEBUG
            // Task {
            //     isHarnessRunning = true
            //     try? await serviceManager.claude.activate()
            //     let report = await serviceManager.claude.runPromptOptimization(timeLimitSeconds: 300)
            //     harnessReport = report
            //     isHarnessRunning = false
            // }
            // #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Re-check permissions when returning from Settings
            if !appState.hasCompletedOnboarding && onboardingRenderer.currentStep == .microphone {
                Task {
                    await serviceManager.refreshPermissions()
                    if serviceManager.permissions.microphone == .granted {
                        advanceOnboarding()
                    } else if let grid = controller.grid {
                        grid.clearLayer(.content)
                        onboardingRenderer.renderContent(into: grid)
                        grid.render()
                    }
                }
            }
        }
        .onChange(of: serviceManager.audioPlayer.state) { _, newState in
            if newState == .playing {
                if let grid = controller.grid {
                    serviceManager.audioPlayer.setDisplayTarget(grid: grid, row: grid.rowCount - 1)
                }
                serviceManager.audioPlayer.startDisplayUpdates()
            } else if newState == .idle {
                serviceManager.audioPlayer.stopDisplayUpdates()
            }
        }
        .onChange(of: serviceManager.progress.resultVersion) { _, _ in
            handleResultUpdate()
        }
        .onChange(of: serviceManager.progress.phase) { _, newPhase in
            if newPhase == .resolved {
                // Context change was cancelled — snapshot already cleared, skip result handling
                let isContextChange = controller.isContextChangeCapture
                if isContextChange && contextChangeSnapshot == nil {
                    return
                }

                // Clear snapshot on successful context change resolution
                if isContextChange {
                    contextChangeSnapshot = nil
                }

                // Tap mode with no Shazam match → return to landing with "nothing observed"
                // Only applies to actual mic observations, not shortcuts/queries
                let context = controller.captureRenderer.queryContext
                let isDirectQuery: Bool = switch context {
                case .shortcut, .subjectChange, .yearChange, .locationChange: true
                case .observation: false
                }
                if !isDirectQuery,
                   serviceManager.progress.mode == .tap,
                   serviceManager.progress.shazamResult == nil {
                    homeRenderer?.showNothingObserved = true
                    if controller.isCapturing && !captureExitInitiated {
                        controller.exitCapture { grid in
                            populateGrid(grid)
                        }
                    } else if !controller.isCapturing {
                        refreshGrid()
                    }
                } else {
                    handleResultUpdate(saveToHistory: true)
                    if controller.isCapturing && !captureExitInitiated {
                        controller.exitCapture { grid in
                            populateGrid(grid)
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showMapSelection) {
            MapSelectionView(
                initialCoordinate: selectedCoordinate,
                onLocationSelected: { coordinate in
                    selectedCoordinate = coordinate
                    showMapSelection = false
                    reverseGeocodeAndQuery(coordinate)
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
                    let changed = year != selectedYear
                    selectedYear = year
                    showYearPicker = false
                    if changed, homeRenderer?.hasObservations == true {
                        queryWithYearChange()
                    }
                },
                onDismiss: { showYearPicker = false }
            )
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if isHarnessRunning {
                Text("HARNESS RUNNING...")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    .padding()
            }
        }
        .sheet(isPresented: Binding(
            get: { harnessReport != nil },
            set: { if !$0 { harnessReport = nil } }
        )) {
            if let report = harnessReport {
                NavigationStack {
                    ScrollView {
                        Text(report)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                    .navigationTitle("Prompt Optimization Report")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { harnessReport = nil }
                        }
                    }
                }
            }
        }
        #endif
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

            // Options page: no SwiftUI buttons — tap overlays handle interactions
        }
    }

    // MARK: - Grid Population

    private func populateGrid(_ grid: CharacterGrid) {
        if appState.hasCompletedOnboarding {
            // Sync autoplay state for options page
            if let optionsRenderer = renderers[.options] as? OptionsPageRenderer {
                optionsRenderer.autoplayEnabled = appState.autoplayEnabled
            }
            // Refresh circa year each time home is rendered without observations
            if navManager.currentPage == .home, homeRenderer?.hasObservations == false {
                refreshCircaYear()
            }
            currentRenderer.renderStructure(into: grid)
            currentRenderer.renderContent(into: grid)
            // Render audio player row on all pages
            serviceManager.audioPlayer.setDisplayTarget(grid: grid, row: grid.rowCount - 1)
            serviceManager.audioPlayer.renderPlayerRow(into: grid, at: grid.rowCount - 1)
        } else {
            onboardingRenderer.renderContent(into: grid)
        }
        grid.render()

        if appState.hasCompletedOnboarding,
           navManager.currentPage == .home,
           homeRenderer?.hasObservations == false,
           homeRenderer?.showNothingObserved != true {
            controller.startIdlePulse()
        }
    }

    private func refreshGrid() {
        guard let grid = controller.grid else { return }
        controller.stopIdlePulse()
        // Sync autoplay state for options page
        if let optionsRenderer = renderers[.options] as? OptionsPageRenderer {
            optionsRenderer.autoplayEnabled = appState.autoplayEnabled
        }
        grid.clearLayer(.content)
        grid.clearLayer(.structure)
        currentRenderer.renderStructure(into: grid)
        currentRenderer.renderContent(into: grid)
        // Render audio player row on all pages
        serviceManager.audioPlayer.setDisplayTarget(grid: grid, row: grid.rowCount - 1)
        serviceManager.audioPlayer.renderPlayerRow(into: grid, at: grid.rowCount - 1)
        grid.render()

        if navManager.currentPage == .home,
           homeRenderer?.hasObservations == false,
           homeRenderer?.showNothingObserved != true {
            controller.startIdlePulse()
        }
    }

    private func handleResultUpdate(saveToHistory: Bool = false) {
        guard let result = serviceManager.progress.latestResult else { return }
        guard let home = homeRenderer else { return }
        controller.stopIdlePulse()

        home.hasObservations = true
        home.graphSubject = GraphSubject(label: result.subject.uppercased())

        // Store connections and build graph items
        home.connections = result.connections
        home.graphItems = result.connections.map { conn in
            GraphItem(
                glyph: conn.entityType.glyph,
                label: conn.name,
                subtitle: conn.subtitle,
                relevance: Float(conn.relevance)
            )
        }

        // Store bio and birthInfo for detail view
        home.bio = result.bio
        home.birthInfo = result.birthInfo

        // Triad rules — location is generally fixed, year flexes with subject relevance.
        let context = controller.captureRenderer.queryContext
        switch context {
        case .yearChange:
            // User picked the year — keep it; location fixed; subject from API
            break
        case .subjectChange:
            // New subject — year flexes to most relevant era; location fixed
            selectedYear = result.year
        case .locationChange:
            // User picked location (already set) — year fixed; subject from API
            break
        case .observation, .shortcut:
            // Fresh observation — update everything from result + GPS
            selectedYear = result.year
            if let loc = serviceManager.progress.location {
                selectedCoordinate = loc.coordinate
                homeRenderer?.locationLabel = LocationService.displayLabel(for: loc)
            }
        }

        // Sync active triad to ServiceManager so observations respect current context
        serviceManager.activeSubject = home.graphSubject.label
        serviceManager.activeYear = selectedYear
        serviceManager.activeLocationLabel = home.locationLabel

        // Save to history only on final resolution (not partial updates)
        if saveToHistory {
            if let activeId = activeHistoryEntryId {
                historyStore.promote(activeId)
                activeHistoryEntryId = nil
            }

            let locationLabel = home.locationLabel
            let entry = HistoryEntry(
                id: UUID(),
                result: result,
                locationLabel: locationLabel,
                latitude: selectedCoordinate.latitude,
                longitude: selectedCoordinate.longitude,
                timestamp: .now
            )
            historyStore.add(entry)
        }

        if controller.isCapturing {
            // Wait until all entity names are resolved before exiting capture.
            // Guard: only call exitCapture once per capture cycle.
            if !captureExitInitiated {
                let hasAllEntities = result.connections.count >= 8
                if hasAllEntities || !result.isPartial {
                    captureExitInitiated = true
                    // Fade out old music when context change map appears;
                    // new playlist loads silently and fades in via transitionToStream.
                    if controller.isContextChangeCapture {
                        serviceManager.audioPlayer.fadeOut()
                    }
                    if contextChangeSnapshot != nil {
                        contextChangeSnapshot = nil
                    }
                    controller.exitCapture { grid in
                        populateGrid(grid)
                    }
                }
            }
        } else {
            captureExitInitiated = false
            refreshGrid()
        }
    }

    private func navigateTo(_ page: Page) {
        guard let targetRenderer = renderers[page] else { return }
        controller.stopIdlePulse()
        navManager.navigate(to: page, using: controller, renderer: targetRenderer)
    }

    private func navigateToInfo() {
        guard let home = homeRenderer, let info = infoRenderer else { return }
        info.configureForSubject(
            name: home.graphSubject.label,
            birthInfo: home.birthInfo,
            bio: home.bio
        )
        navigateTo(.info)
    }

    private func navigateToEntityInfo(_ connection: CultureConnection) {
        guard let info = infoRenderer else { return }
        info.configureForEntity(connection)

        // Switch playlist based on entity type
        if connection.entityType.hasArtistCatalog || connection.entityType == .creation {
            serviceManager.switchToEntityPlaylist(connection: connection)
        }

        navigateTo(.info)

        // Fetch Tier 3 entity detail (may already be cached from preload)
        if let result = serviceManager.progress.latestResult {
            Task {
                if let detail = await serviceManager.claude.getEntityDetail(
                    for: connection, subject: result.subject,
                    place: result.place, year: result.year
                ) {
                    info.entityDescription = detail.description
                }
            }
        }
    }

    private func resetToObservePage() {
        guard let home = homeRenderer else { return }
        home.hasObservations = false
        activeHistoryEntryId = nil
        refreshCircaYear()

        guard let targetRenderer = renderers[.home] else { return }
        navManager.navigateToHome(using: controller, renderer: targetRenderer) {
            guard let grid = controller.grid else { return }
            serviceManager.audioPlayer.setDisplayTarget(grid: grid, row: grid.rowCount - 1)
            serviceManager.audioPlayer.renderPlayerRow(into: grid, at: grid.rowCount - 1)
            grid.render()
            controller.startIdlePulse()
        }
    }

    private func goBack() {
        // If leaving an entity page with artist playlist, switch back to general
        if navManager.currentPage == .info, infoRenderer?.mode == .entity {
            serviceManager.switchToGeneralPlaylist()
        }

        let previousPage = navManager.pageStack.last ?? .home
        guard let targetRenderer = renderers[previousPage] else { return }
        navManager.goBack(using: controller, renderer: targetRenderer) {
            guard let grid = controller.grid else { return }
            serviceManager.audioPlayer.setDisplayTarget(grid: grid, row: grid.rowCount - 1)
            serviceManager.audioPlayer.renderPlayerRow(into: grid, at: grid.rowCount - 1)
            grid.render()
            if previousPage == .home,
               homeRenderer?.hasObservations == false,
               homeRenderer?.showNothingObserved != true {
                controller.startIdlePulse()
            }
        }
    }

    private func restoreFromHistory(_ entry: HistoryEntry) {
        guard let home = homeRenderer else { return }

        activeHistoryEntryId = entry.id

        // Restore home page state from history entry
        let result = entry.result
        home.hasObservations = true
        home.graphSubject = GraphSubject(label: result.subject.uppercased())
        home.connections = result.connections
        home.graphItems = result.connections.map { conn in
            GraphItem(
                glyph: conn.entityType.glyph,
                label: conn.name,
                subtitle: conn.subtitle,
                relevance: Float(conn.relevance)
            )
        }
        home.bio = result.bio
        home.birthInfo = result.birthInfo
        home.locationLabel = entry.locationLabel

        selectedYear = result.year
        selectedCoordinate = CLLocationCoordinate2D(
            latitude: entry.latitude,
            longitude: entry.longitude
        )

        // Rebuild audio player queue for the restored subject (fade transition)
        serviceManager.buildPlayerQueue(from: result, transition: true)

        goBack()
    }

    private func makeEntitySubject() {
        guard let info = infoRenderer, info.mode == .entity else { return }
        contextChangeSnapshot = createContextSnapshot()

        // Find the matching connection for full entity context
        let connection = homeRenderer?.connections.first { $0.name == info.entityName }
        let entityName = info.entityName
        let priorSubject = homeRenderer?.graphSubject.label ?? ""
        let location = homeRenderer?.locationLabel ?? ""

        // Reset nav to home silently — exitCapture will restore home content
        navManager.resetToHome()

        // Go directly into capture/analysis from the current page
        serviceManager.querySubjectChange(
            connection: connection,
            newSubject: entityName,
            priorSubject: priorSubject,
            location: location,
            year: selectedYear
        )
        controller.enterCapture(
            mode: .observing,
            progress: serviceManager.progress,
            audioService: serviceManager.audio,
            contextYear: selectedYear,
            queryContext: .subjectChange(entityName),
            onWipeOutComplete: {}
        )
    }

    private func queryWithYearChange() {
        guard let home = homeRenderer, home.hasObservations else { return }
        contextChangeSnapshot = createContextSnapshot()
        let subject = home.graphSubject.label
        let location = home.locationLabel

        // Year change: year + location are fixed, subject is flexible
        serviceManager.queryYearChange(
            subject: subject,
            year: selectedYear,
            location: location
        )
        controller.enterCapture(
            mode: .observing,
            progress: serviceManager.progress,
            audioService: serviceManager.audio,
            contextYear: selectedYear,
            queryContext: .yearChange(selectedYear),
            onWipeOutComplete: {}
        )
    }

    private func queryWithLocationChange(newLocation: String, locationResult: LocationResult? = nil) {
        guard let home = homeRenderer, home.hasObservations else { return }
        contextChangeSnapshot = createContextSnapshot()
        let subject = home.graphSubject.label
        let subjectType = serviceManager.progress.latestResult?.subjectType ?? "artist"

        // Location change: subject + year are fixed, location is new
        serviceManager.queryLocationChange(
            subject: subject,
            subjectType: subjectType,
            year: selectedYear,
            location: newLocation,
            locationResult: locationResult
        )
        controller.enterCapture(
            mode: .observing,
            progress: serviceManager.progress,
            audioService: serviceManager.audio,
            contextYear: selectedYear,
            queryContext: .locationChange(newLocation, priorSubject: subject),
            onWipeOutComplete: {}
        )
    }

    // MARK: - Onboarding Component Layer

    @ViewBuilder
    private func onboardingComponentLayer(metrics: GridMetrics) -> some View {
        if onboardingRenderer.currentStep == .welcome {
            let logoHeight = CGFloat(6) * metrics.lineHeight * 0.825
            Image("anaspace-onboarding-logo")
                .resizable()
                .scaledToFit()
                .frame(height: logoHeight)
                .frame(maxWidth: .infinity)
                .offset(
                    y: GridMetrics.topPadding + CGFloat(onboardingRenderer.logoRow) * metrics.lineHeight + 150
                )
        }
    }

    // MARK: - Onboarding Navigation

    private func handleOnboardingTap() {
        switch onboardingRenderer.currentStep {
        case .welcome:
            advanceOnboarding()
        case .microphone:
            if onboardingRenderer.isMicDenied {
                openSettings()
                return
            }
            Task {
                await serviceManager.permissions.requestMicrophone()
                if serviceManager.permissions.microphone == .granted {
                    advanceOnboarding()
                } else {
                    // Re-render to show mic-denied state
                    guard let grid = controller.grid else { return }
                    grid.clearLayer(.content)
                    onboardingRenderer.renderContent(into: grid)
                    grid.render()
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
                completeOnboarding()
            }
        }
    }

    private func advanceOnboarding() {
        guard let grid = controller.grid else { return }
        isOnboardingTransitioning = true
        controller.wipe.wipeOut(on: grid) { [self] in
            // Advance to next step, skipping already-granted permissions
            var next: OnboardingStep? = switch onboardingRenderer.currentStep {
            case .welcome: .microphone
            case .microphone: .location
            case .location: .speech
            case .speech: nil
            }

            // Skip granted permissions in a loop
            while let candidate = next, onboardingRenderer.currentStep != candidate {
                onboardingRenderer.currentStep = candidate
                if onboardingRenderer.shouldSkipCurrentStep {
                    next = switch candidate {
                    case .welcome: .microphone
                    case .microphone: .location
                    case .location: .speech
                    case .speech: nil
                    }
                } else {
                    break
                }
            }

            // If all remaining permissions granted, complete onboarding
            if next == nil {
                appState.hasCompletedOnboarding = true
                grid.clearLayer(.content)
                grid.clearLayer(.structure)
                populateGrid(grid)
                controller.wipe.wipeIn(on: grid) { [self] in
                    isOnboardingTransitioning = false
                }
                return
            }

            grid.clearLayer(.content)
            grid.clearLayer(.structure)
            onboardingRenderer.renderContent(into: grid)
            grid.render()
            controller.wipe.wipeIn(on: grid) { [self] in
                isOnboardingTransitioning = false
            }
        }
    }

    private func completeOnboarding() {
        guard let grid = controller.grid else { return }
        isOnboardingTransitioning = true
        controller.wipe.wipeOut(on: grid) { [self] in
            appState.hasCompletedOnboarding = true
            grid.clearLayer(.content)
            grid.clearLayer(.structure)
            populateGrid(grid)
            controller.wipe.wipeIn(on: grid) { [self] in
                isOnboardingTransitioning = false
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func reverseGeocodeAndQuery(_ coordinate: CLLocationCoordinate2D) {
        Task {
            guard let result = await serviceManager.location.reverseGeocode(coordinate) else { return }
            let newLabel = LocationService.displayLabel(for: result)
            homeRenderer?.locationLabel = newLabel

            if homeRenderer?.hasObservations == true {
                queryWithLocationChange(newLocation: newLabel, locationResult: result)
            } else {
                refreshGrid()
            }
        }
    }

    // MARK: - Idea Card Shortcuts

    private func generateCircaYear() -> Int {
        let currentYear = Calendar.current.component(.year, from: Date())
        let maxYear = currentYear - 20
        let minYear = 1920

        // Try up to 50 times to find a non-repeated year
        for _ in 0..<50 {
            let year: Int
            // 60% chance of landing in 1960-1989 (golden era bias)
            if Double.random(in: 0..<1) < 0.6 {
                year = Int.random(in: 1960...1989)
            } else {
                year = Int.random(in: minYear...maxYear)
            }
            if !usedCircaYears.contains(year) {
                usedCircaYears.insert(year)
                return year
            }
        }
        // Fallback: just pick any year in range
        let year = Int.random(in: minYear...maxYear)
        usedCircaYears.insert(year)
        return year
    }

    private func handleIdeaCardTap(index: Int) {
        guard serviceManager.progress.phase == .idle || serviceManager.progress.phase == .resolved else { return }
        homeRenderer?.showNothingObserved = false

        // Build location string from current GPS
        let locationLabel: String
        if let loc = serviceManager.location.currentResult {
            locationLabel = LocationService.displayLabel(for: loc)
        } else {
            locationLabel = homeRenderer?.locationLabel ?? "UNKNOWN"
        }

        let circaYear = homeRenderer?.circaYear ?? 1975

        let prompt: String
        let title: String
        var contextYear: Int? = nil

        // NOTE: On-device model (~3B params) needs short, direct questions.
        // Complex multi-sentence prompts cause hallucination.
        switch index {
        case 0:
            // WHAT'S HOT / RIGHT HERE — implies current year
            title = "WHAT'S HOT RIGHT HERE"
            contextYear = Calendar.current.component(.year, from: Date())
            prompt = "Which music artist FROM \(locationLabel) is most popular right now? Answer with just the name."

        case 1:
            // WHO SHAPED / THIS PLACE
            title = "WHO SHAPED THIS PLACE"
            prompt = "Which music artist FROM \(locationLabel) was most influential? Answer with just the name."

        case 2:
            // THIS SPOT / CIRCA {YEAR}
            title = "THIS SPOT CIRCA \(circaYear)"
            contextYear = circaYear
            prompt = "Which music artist FROM \(locationLabel) was most popular in \(circaYear)? Answer with just the name."

        case 3:
            // WORDS THAT / MADE SONGS
            title = "WORDS THAT MADE SONGS"
            prompt = "Which poet or writer FROM \(locationLabel) most influenced music? Answer with just the name."

        default:
            return
        }

        // Enter capture/evaluation flow
        navManager.resetToHome()
        serviceManager.queryShortcut(prompt: prompt, locationLabel: locationLabel, contextYear: contextYear ?? 0)
        controller.enterCapture(
            mode: .observing,
            progress: serviceManager.progress,
            audioService: serviceManager.audio,
            contextYear: contextYear,
            queryContext: .shortcut(title),
            onWipeOutComplete: {}
        )
    }

    private func refreshCircaYear() {
        homeRenderer?.circaYear = generateCircaYear()
    }

    // MARK: - Context Change Snapshot & Cancel

    private func createContextSnapshot() -> ContextChangeSnapshot {
        let home = homeRenderer
        return ContextChangeSnapshot(
            hasObservations: home?.hasObservations ?? false,
            graphSubject: home?.graphSubject ?? GraphSubject(label: ""),
            graphItems: home?.graphItems ?? [],
            connections: home?.connections ?? [],
            bio: home?.bio ?? "",
            birthInfo: home?.birthInfo ?? "",
            locationLabel: home?.locationLabel ?? "",
            selectedYear: selectedYear,
            selectedCoordinate: selectedCoordinate,
            activeHistoryEntryId: activeHistoryEntryId
        )
    }

    private func cancelContextChange() {
        guard let snapshot = contextChangeSnapshot else { return }

        // Cancel Claude task, reset progress
        serviceManager.cancelContextChange()

        // Restore home renderer state
        if let home = homeRenderer {
            home.hasObservations = snapshot.hasObservations
            home.graphSubject = snapshot.graphSubject
            home.graphItems = snapshot.graphItems
            home.connections = snapshot.connections
            home.bio = snapshot.bio
            home.birthInfo = snapshot.birthInfo
            home.locationLabel = snapshot.locationLabel
        }

        // Restore triad state
        selectedYear = snapshot.selectedYear
        selectedCoordinate = snapshot.selectedCoordinate
        activeHistoryEntryId = snapshot.activeHistoryEntryId

        // Audio player keeps playing — no fade was applied for context changes

        // Exit capture with restored content
        controller.exitCapture { grid in
            populateGrid(grid)
        }

        contextChangeSnapshot = nil
    }
}

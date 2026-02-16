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
    @State private var historyStore = HistoryStore()
    @State private var activeHistoryEntryId: UUID?
    @State private var usedCircaYears: Set<Int> = []

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
                .overlay(alignment: .topLeading) {
                    // Tap overlay for subject label in radial graph center
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .home,
                       homeRenderer?.hasObservations == true,
                       let metrics = controller.metrics {
                        let graphStartRow = 11
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
                            .onTapGesture { navigateToInfo() }
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
                        ForEach(home.placements, id: \.index) { placement in
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(
                                    width: CGFloat(placement.width) * metrics.cellWidth,
                                    height: CGFloat(placement.height) * metrics.lineHeight
                                )
                                .offset(
                                    x: GridMetrics.sideMargin + CGFloat(placement.col) * metrics.cellWidth,
                                    y: GridMetrics.topPadding + CGFloat(placement.row) * metrics.lineHeight
                                )
                                .onTapGesture {
                                    guard placement.index < home.connections.count else { return }
                                    navigateToEntityInfo(home.connections[placement.index])
                                }
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // Tap overlays for history entries
                    if appState.hasCompletedOnboarding,
                       !controller.isCapturing,
                       navManager.currentPage == .history,
                       let history = historyRenderer,
                       let metrics = controller.metrics {
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
                                    handleIdeaCardTap(index: index)
                                }
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
                    if !appState.hasCompletedOnboarding {
                        Spacer()
                    } else if navManager.currentPage == .home {
                        BottomNavBar(
                            isObserving: controller.isObserving,
                            onObserveTap: {
                                guard serviceManager.progress.phase == .idle else { return }
                                activeHistoryEntryId = nil
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
                    } else {
                        HStack {
                            NavButton(
                                iconName: "arrow-back",
                                fg: GridColor.background.uiColor.swiftUI,
                                bg: GridColor.bold.uiColor.swiftUI
                            ) {
                                goBack()
                            }
                            Spacer()
                            if navManager.currentPage == .info,
                               infoRenderer?.mode == .entity {
                                NavTextButton(
                                    label: "+ SUBJECT",
                                    fg: GridColor.background.uiColor.swiftUI,
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
        .statusBarHidden()
        .task {
            historyStore.load()
            serviceManager.appState = appState
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
        .onChange(of: serviceManager.progress.latestResult?.narrative) { _, _ in
            handleResultUpdate()
        }
        .onChange(of: serviceManager.progress.phase) { _, newPhase in
            if newPhase == .resolved {
                handleResultUpdate(saveToHistory: true)
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
                    let autoplayLabel = appState.autoplayEnabled ? "AUTOPLAY   ON" : "AUTOPLAY  OFF"
                    let labels = [autoplayLabel, "LOG OUT", "UNLINK", "DOWNLOAD DATA"]
                    let rows = optionsRenderer.settingsRows
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index < labels.count {
                            GridButton(label: labels[index], metrics: metrics) {
                                if index == 0 {
                                    appState.autoplayEnabled.toggle()
                                    refreshGrid()
                                }
                            }
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
            // Content first — computes hiddenStructureRows for buttons
            onboardingRenderer.renderContent(into: grid)
            onboardingRenderer.renderStructure(into: grid)
        }
        grid.render()
    }

    private func refreshGrid() {
        guard let grid = controller.grid else { return }
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
    }

    private func handleResultUpdate(saveToHistory: Bool = false) {
        guard let result = serviceManager.progress.latestResult else { return }
        guard let home = homeRenderer else { return }

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

        selectedYear = result.year

        // Update location from progress
        if let loc = serviceManager.progress.location {
            selectedCoordinate = loc.coordinate
            homeRenderer?.locationLabel = LocationService.displayLabel(for: loc)
        }

        // Save to history only on final resolution (not streaming updates)
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

        // Only refresh grid if not in capture mode — exitCapture will handle it
        if !controller.isCapturing {
            refreshGrid()
        }
    }

    private func navigateTo(_ page: Page) {
        guard let targetRenderer = renderers[page] else { return }
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
    }

    private func goBack() {
        // If leaving an entity page with artist playlist, switch back to general
        if navManager.currentPage == .info, infoRenderer?.mode == .entity {
            serviceManager.switchToGeneralPlaylist()
        }

        let previousPage = navManager.pageStack.last ?? .home
        guard let targetRenderer = renderers[previousPage] else { return }
        navManager.goBack(using: controller, renderer: targetRenderer)
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
        let entityName = info.entityName

        // Reset nav to home silently — exitCapture will restore home content
        navManager.resetToHome()

        // Go directly into capture/analysis from the current page
        serviceManager.querySubject(entityName)
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
        let subject = home.graphSubject.label

        // Location change: subject + year are fixed, location is new
        serviceManager.queryLocationChange(
            subject: subject,
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

        // Build location string from current GPS
        let locationLabel: String
        if let loc = serviceManager.location.currentResult {
            locationLabel = LocationService.displayLabel(for: loc)
        } else {
            locationLabel = homeRenderer?.locationLabel ?? "UNKNOWN"
        }

        let currentDate = Date().formatted(date: .long, time: .omitted)
        let circaYear = homeRenderer?.circaYear ?? 1975

        let prompt: String
        let title: String
        var contextYear: Int? = nil

        switch index {
        case 0:
            // WHAT'S HOT / RIGHT HERE
            title = "WHAT'S HOT RIGHT HERE"
            prompt = """
            The user is at \(locationLabel) on \(currentDate). Who is the most culturally relevant music artist connected to this place right now? Focus on artists who are currently active, trending, or have a deep cultural resonance with this specific location today. The year should be the current year.
            """

        case 1:
            // WHO SHAPED / THIS PLACE
            title = "WHO SHAPED THIS PLACE"
            prompt = """
            The user is at \(locationLabel). Who is the single most culturally influential music artist or creator whose legacy is inseparable from this place? Focus on the artist who most defined the cultural identity of this location. The year should be their peak era of influence.
            """

        case 2:
            // THIS SPOT / CIRCA {YEAR}
            title = "THIS SPOT CIRCA \(circaYear)"
            contextYear = circaYear
            prompt = """
            The user is at \(locationLabel). The year is \(circaYear). Who was the most culturally significant music artist or creator connected to this place during this era? Focus on the artist who best represents the cultural moment of this location at that time. The year should be \(circaYear).
            """

        case 3:
            // WORDS THAT / MADE SONGS
            title = "WORDS THAT MADE SONGS"
            prompt = """
            The user is at \(locationLabel). Find the most significant poet, writer, or literary figure whose words directly influenced or became music connected to this place. Focus on the literary-to-music bridge — someone whose writing was adapted, sampled, or deeply influenced songwriting in this location's musical tradition. The year should reflect their peak period of influence on music.
            """

        default:
            return
        }

        // Enter capture/evaluation flow
        navManager.resetToHome()
        serviceManager.queryShortcut(prompt: prompt)
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
}

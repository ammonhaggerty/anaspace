import Foundation

@Observable @MainActor
final class GridController {
    var grid: CharacterGrid?
    var metrics: GridMetrics?
    var isObserving = false
    var isCapturing = false
    var isEvaluating = false
    var isContextChangeCapture = false
    let cascade = CascadeAnimation()
    let observe = ObserveAnimation()
    let wipe = WipeAnimation()
    let idlePulse = IdlePulseAnimation()
    let captureRenderer = CaptureRenderer()

    // Queued restore closure for edge case: exitCapture called during wipe
    private var pendingRestore: ((CharacterGrid) -> Void)?

    // Track hold upgrade that arrives before wipe completes
    private var pendingHoldUpgrade = false

    func triggerCascade() {
        guard let grid else { return }
        cascade.run(on: grid) {}
    }

    // MARK: - Idle Pulse

    func startIdlePulse() {
        guard let grid, !idlePulse.isRunning else { return }
        idlePulse.run(on: grid) {}
    }

    func stopIdlePulse() {
        guard idlePulse.isRunning else { return }
        idlePulse.cancel()
    }

    // MARK: - Capture Flow

    func enterCapture(
        mode: CaptureRenderer.Mode,
        progress: ObservationProgress,
        audioService: AudioService,
        contextYear: Int? = nil,
        queryContext: CaptureRenderer.QueryContext = .observation,
        onWipeOutComplete: @escaping () -> Void
    ) {
        guard let grid, !isCapturing else { return }
        isCapturing = true
        isObserving = true
        pendingHoldUpgrade = false
        isEvaluating = false
        isContextChangeCapture = switch queryContext {
        case .yearChange, .locationChange, .subjectChange: true
        case .observation, .shortcut: false
        }
        idlePulse.cancel()

        wipe.wipeOut(on: grid) { [weak self] in
            guard let self, let grid = self.grid else { return }
            onWipeOutComplete()

            // Clear content + structure, fill structure with ░ (leave last row for audio player)
            grid.clearLayer(.content)
            grid.clearLayer(.structure)
            let cols = GridMetrics.columns
            let fillState = CellState(character: "\u{2591}", color: .tint, bold: false)
            for row in 2..<(grid.rowCount - 1) {
                let states = [CellState](repeating: fillState, count: cols)
                grid.setRow(layer: .structure, row: row, states: states)
            }

            // Use upgraded mode if hold happened during wipe
            let effectiveMode: CaptureRenderer.Mode = self.pendingHoldUpgrade ? .listening : mode

            // Start CaptureRenderer
            self.captureRenderer.onTransitionToEvaluating = { [weak self] in
                self?.transitionToEvaluating()
            }
            self.captureRenderer.start(
                on: grid,
                mode: effectiveMode,
                progress: progress,
                audioService: audioService,
                contextYear: contextYear,
                queryContext: queryContext
            )

            // Only run ObserveAnimation for observing mode (not listening)
            if effectiveMode == .observing {
                let lastRow = grid.rowCount - 1
                self.observe.config.isIndefinite = true
                self.observe.config.skipRows = [0, 1, lastRow]
                self.observe.run(on: grid) {}
            }

            // Reveal capture view
            self.wipe.wipeIn(on: grid) { [weak self] in
                // Check for queued exit
                if let restore = self?.pendingRestore {
                    self?.pendingRestore = nil
                    self?.performExit(restore: restore)
                }
            }
        }
    }

    func exitCapture(restore: @escaping (CharacterGrid) -> Void) {
        // Cancel any running wipe to ensure cleanup always runs
        if wipe.isRunning {
            wipe.cancel()
        }
        pendingRestore = nil
        performExit(restore: restore)
    }

    func upgradeCaptureToHold() {
        if wipe.isRunning {
            // Wipe still in progress — flag for when CaptureRenderer starts
            pendingHoldUpgrade = true
        } else {
            // CaptureRenderer already running — upgrade live
            captureRenderer.upgradeToListening()
            // Stop observe animation for listening mode
            observe.cancel()
        }
    }

    func transitionToEvaluating() {
        guard let grid else { return }
        isEvaluating = true

        // Clear structure rows 2-3 for signal carousel breathing room
        grid.clearRow(layer: .structure, row: 2)
        grid.clearRow(layer: .structure, row: 3)

        // Start observe animation with contracting circles if not already running
        let lastRow = grid.rowCount - 1
        if !observe.isRunning {
            observe.config.isIndefinite = true
            observe.config.skipRows = [0, 1, 2, 3, lastRow]
            observe.config.isEvaluating = true
            observe.run(on: grid) {}
        } else {
            // Expand observe animation skipRows and switch to contracting circles
            observe.config.skipRows = [0, 1, 2, 3, lastRow]
            observe.config.isEvaluating = true
            observe.resetWaves()
        }

        // Clear any transcript or leftover content on rows 2+ (leave last row for audio player)
        for row in 2..<(grid.rowCount - 1) {
            grid.clearRow(layer: .content, row: row)
        }

        grid.render()
    }

    // MARK: - Private

    private func performExit(restore: @escaping (CharacterGrid) -> Void) {
        guard let grid else { return }

        // Stop live renderers
        captureRenderer.stop()
        observe.cancel()

        wipe.wipeOut(on: grid) { [weak self] in
            guard let self, let grid = self.grid else { return }

            // Clear all layers and populate results
            grid.clearLayer(.content)
            grid.clearLayer(.structure)
            grid.clearLayer(.transition)
            restore(grid)

            // Reveal results
            self.wipe.wipeIn(on: grid) { [weak self] in
                self?.isCapturing = false
                self?.isObserving = false
                self?.isEvaluating = false
                self?.isContextChangeCapture = false
                self?.pendingHoldUpgrade = false
                self?.observe.config.isIndefinite = false
                self?.observe.config.skipRows = []
                self?.observe.config.isEvaluating = false
            }
        }
    }
}

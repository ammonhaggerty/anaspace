import Foundation

@Observable @MainActor
final class GridController {
    var grid: CharacterGrid?
    var metrics: GridMetrics?
    var isObserving = false
    var isCapturing = false
    let cascade = CascadeAnimation()
    let observe = ObserveAnimation()
    let wipe = WipeAnimation()
    let captureRenderer = CaptureRenderer()

    // Queued restore closure for edge case: exitCapture called during wipe
    private var pendingRestore: ((CharacterGrid) -> Void)?

    func triggerCascade() {
        guard let grid else { return }
        cascade.run(on: grid) {}
    }

    // MARK: - Capture Flow

    func enterCapture(
        mode: CaptureRenderer.Mode,
        progress: ObservationProgress,
        audioService: AudioService,
        onWipeOutComplete: @escaping () -> Void
    ) {
        guard let grid, !isCapturing else { return }
        isCapturing = true
        isObserving = true

        wipe.wipeOut(on: grid) { [weak self] in
            guard let self, let grid = self.grid else { return }
            onWipeOutComplete()

            // Clear content + structure, fill structure with ░
            grid.clearLayer(.content)
            grid.clearLayer(.structure)
            let cols = GridMetrics.columns
            let fillState = CellState(character: "\u{2591}", color: .tint, bold: false)
            for row in 2..<grid.rowCount {
                let states = [CellState](repeating: fillState, count: cols)
                grid.setRow(layer: .structure, row: row, states: states)
            }

            // Start CaptureRenderer
            self.captureRenderer.onTransitionToEvaluating = { [weak self] in
                self?.transitionToEvaluating()
            }
            self.captureRenderer.start(
                on: grid,
                mode: mode,
                progress: progress,
                audioService: audioService
            )

            // Start ObserveAnimation (indefinite, skip header rows)
            self.observe.config.isIndefinite = true
            self.observe.config.skipRows = [0, 1]
            self.observe.run(on: grid) {}

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
        // If a wipe is currently running, queue the restore
        if wipe.isRunning {
            pendingRestore = restore
            return
        }
        performExit(restore: restore)
    }

    func upgradeCaptureToHold() {
        captureRenderer.upgradeToListening()
    }

    func transitionToEvaluating() {
        guard let grid else { return }

        // Clear structure rows 2-3 for signal carousel breathing room
        grid.clearRow(layer: .structure, row: 2)
        grid.clearRow(layer: .structure, row: 3)

        // Expand observe animation skipRows to include rows 2-3
        observe.config.skipRows = [0, 1, 2, 3]

        // Clear any transcript or leftover content on rows 2+
        for row in 2..<grid.rowCount {
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
                self?.observe.config.isIndefinite = false
                self?.observe.config.skipRows = []
            }
        }
    }
}

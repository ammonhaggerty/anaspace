import Foundation

enum OnboardingStep {
    case welcome
    case microphone
    case location
    case speech
    case tips
}

@Observable @MainActor
final class OnboardingRenderer {

    var currentStep: OnboardingStep = .welcome
    var permissions: PermissionManager?

    // Button row tracking for component layer
    private(set) var continueButtonRow: Int = 0
    private(set) var settingsButtonRow: Int = -1

    // Rows where structure should be hidden (around buttons)
    private(set) var hiddenStructureRows: Set<Int> = []

    private let cols = GridMetrics.columns
    private let contentWidth = 31

    /// True if the current permission step is already granted and should be skipped.
    var shouldSkipCurrentStep: Bool {
        guard let permissions else { return false }
        switch currentStep {
        case .microphone: return permissions.microphone == .granted
        case .location: return permissions.location == .granted
        case .speech: return permissions.speechRecognition == .granted
        default: return false
        }
    }

    /// True if current step's permission was denied (mic only blocks progress).
    var isMicDenied: Bool {
        permissions?.microphone == .denied
    }

    // MARK: - Structure

    func renderStructure(into grid: CharacterGrid) {
        for row in 0..<grid.rowCount {
            guard !hiddenStructureRows.contains(row) else { continue }
            for col in 0..<cols {
                grid.setCell(
                    layer: .structure, row: row, col: col,
                    state: CellState(character: "\u{2591}", color: .tint, bold: false)
                )
            }
        }
    }

    // MARK: - Content

    func renderContent(into grid: CharacterGrid) {
        hiddenStructureRows = []
        settingsButtonRow = -1
        switch currentStep {
        case .welcome:
            renderWelcome(into: grid)
        case .microphone:
            renderMicrophone(into: grid)
        case .location:
            renderLocation(into: grid)
        case .speech:
            renderSpeech(into: grid)
        case .tips:
            renderTips(into: grid)
        }
    }

    // MARK: - Welcome Screen

    private func renderWelcome(into grid: CharacterGrid) {
        let logoLines: [String] = [
            "        \u{250F}\u{2513}\u{2533}\u{2513}\u{250F}\u{2513}\u{250F}\u{2513}\u{250F}\u{2513}\u{250F}\u{2513}\u{250F}\u{2513}\u{250F}\u{2513}",
            "        \u{2523}\u{252B}\u{2503}\u{2503}\u{2523}\u{252B}\u{2517}\u{2513}\u{2503}\u{2503}\u{2523}\u{252B}\u{2503} \u{2523} ",
            "       \u{257C}\u{251B}\u{2517}\u{251B}\u{2517}\u{251B}\u{2517}\u{2517}\u{251B}\u{2523}\u{251B}\u{251B}\u{2517}\u{2517}\u{251B}\u{2517}\u{251B}",
        ]

        var row = 1

        for line in logoLines {
            guard row < grid.rowCount else { break }
            for (i, ch) in line.enumerated() {
                guard i < cols else { break }
                guard ch != " " else { continue }
                grid.setCell(
                    layer: .content, row: row, col: i,
                    state: CellState(character: ch, color: .bold, bold: true)
                )
            }
            row += 1
        }

        grid.setCell(
            layer: .content, row: row, col: cols / 2,
            state: CellState(character: "\u{25CF}", color: .focus, bold: false)
        )
        row += 1

        row += 1 // spacer

        row = renderCenteredParagraph("A CULTURAL EXPLORATION ENGINE", into: grid, row: row)

        row += 1 // spacer

        row = renderCenteredHeader("YOUR DATA IS YOURS", into: grid, row: row)
        row = renderCenteredParagraph(
            "Everything lives on your device. No data collection. No accounts. No tracking. Your discoveries belong to you.",
            into: grid, row: row
        )

        row += 2
        markButtonRows(row)
        continueButtonRow = row
    }

    // MARK: - Microphone Screen (Required)

    private func renderMicrophone(into grid: CharacterGrid) {
        var row = 1

        if permissions?.microphone == .denied {
            // Denied state
            row = renderCenteredHeader("MICROPHONE REQUIRED", into: grid, row: row)
            row += 1
            row = renderCenteredParagraph(
                "Microphone access was denied. Open Settings to enable microphone access for Anaspace.",
                into: grid, row: row
            )

            row += 2
            markButtonRows(row)
            settingsButtonRow = row
            continueButtonRow = -1
        } else {
            // Pre-read state
            row = renderCenteredHeader("MICROPHONE", into: grid, row: row)
            row += 1
            row = renderCenteredParagraph(
                "The core experience uses the microphone to identify music and classify the sound around you.",
                into: grid, row: row
            )
            row += 1
            row = renderCenteredParagraph(
                "You will be asked to give permission.",
                into: grid, row: row
            )

            row += 2
            markButtonRows(row)
            continueButtonRow = row
        }
    }

    // MARK: - Location Screen (Recommended)

    private func renderLocation(into grid: CharacterGrid) {
        var row = 1

        row = renderCenteredHeader("LOCATION", into: grid, row: row)
        row += 1
        row = renderCenteredParagraph(
            "Location anchors your discoveries to place, connecting what you hear to where you are.",
            into: grid, row: row
        )
        row += 1
        row = renderCenteredParagraph(
            "You will be asked to share your location.",
            into: grid, row: row
        )

        row += 2
        markButtonRows(row)
        continueButtonRow = row
    }

    // MARK: - Speech Screen (Optional)

    private func renderSpeech(into grid: CharacterGrid) {
        var row = 1

        row = renderCenteredHeader("SPEECH", into: grid, row: row)
        row += 1
        row = renderCenteredParagraph(
            "Speech recognition powers walkie-talkie mode. Press and hold to speak a command, name an artist, or describe a moment.",
            into: grid, row: row
        )
        row += 1
        row = renderCenteredParagraph(
            "You will be asked to enable speech recognition.",
            into: grid, row: row
        )

        row += 2
        markButtonRows(row)
        continueButtonRow = row
    }

    // MARK: - Tips Screen

    private func renderTips(into grid: CharacterGrid) {
        var row = 1

        row = renderCenteredHeader("HOW IT WORKS", into: grid, row: row)
        row += 1
        row = renderCenteredHeader("TAP", into: grid, row: row)
        row = renderCenteredParagraph(
            "Listen to the world. Identifies music, classifies sound, captures location. Resolves automatically on match or timeout.",
            into: grid, row: row
        )
        row += 1
        row = renderCenteredHeader("PRESS & HOLD", into: grid, row: row)
        row = renderCenteredParagraph(
            "Walkie-talkie mode. Speak a command, name an artist, describe a moment. Release when done.",
            into: grid, row: row
        )

        row += 2
        markButtonRows(row)
        continueButtonRow = row
    }

    // MARK: - Centered Rendering Helpers

    private func renderCenteredHeader(_ text: String, into grid: CharacterGrid, row: Int) -> Int {
        guard row < grid.rowCount else { return row }
        let uppercased = text.uppercased()
        let startCol = max(0, (cols - uppercased.count) / 2)
        for (i, ch) in uppercased.enumerated() {
            guard startCol + i < cols else { break }
            grid.setCell(
                layer: .content, row: row, col: startCol + i,
                state: CellState(character: ch, color: .bold, bold: true)
            )
        }
        return row + 1
    }

    private func renderCenteredParagraph(_ text: String, into grid: CharacterGrid, row: Int) -> Int {
        let lines = TextWrapper.wrap(text, maxWidth: contentWidth)
        var currentRow = row
        for line in lines {
            guard currentRow < grid.rowCount else { break }
            let startCol = max(0, (cols - line.count) / 2)
            for (i, ch) in line.enumerated() {
                guard startCol + i < cols else { break }
                grid.setCell(
                    layer: .content, row: currentRow, col: startCol + i,
                    state: CellState(character: ch, color: .bold, bold: false)
                )
            }
            currentRow += 1
        }
        return currentRow
    }

    private func markButtonRows(_ buttonRow: Int) {
        hiddenStructureRows.formUnion([buttonRow - 1, buttonRow, buttonRow + 1])
    }
}

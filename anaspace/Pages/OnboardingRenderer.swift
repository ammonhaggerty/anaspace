import Foundation

enum OnboardingStep {
    case welcome
    case microphone
    case location
    case speech
}

@Observable @MainActor
final class OnboardingRenderer {

    var currentStep: OnboardingStep = .welcome
    var permissions: PermissionManager?

    // Button region for pressed-state rendering (row, col, width, height)
    private(set) var buttonRegion: (row: Int, col: Int, width: Int, height: Int) = (0, 0, 0, 0)

    // Logo row for component layer positioning
    private(set) var logoRow: Int = 0

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
        // No background structure in redesigned onboarding
    }

    // MARK: - Content

    func renderContent(into grid: CharacterGrid) {
        switch currentStep {
        case .welcome:
            renderWelcome(into: grid)
        case .microphone:
            if isMicDenied {
                renderMicDenied(into: grid)
            } else {
                renderPermission(into: grid, glyph: "\u{25C9}", header: "MICROPHONE ACCESS",
                                 subtitle: "TO OBSERVE\nANASPACE NEEDS TO LISTEN", buttonLabel: "READY")
            }
        case .location:
            renderPermission(into: grid, glyph: "\u{2207}", header: "LOCATION ACCESS",
                             subtitle: "EVERY SOUND HAS A PLACE", buttonLabel: "READY")
        case .speech:
            renderPermission(into: grid, glyph: "\u{238A}", header: "SPEECH ACCESS",
                             subtitle: "YOUR VOICE IS A COMPASS TOO", buttonLabel: "READY")
        }
    }

    // MARK: - Welcome Screen

    private func renderWelcome(into grid: CharacterGrid) {
        let rowCount = grid.rowCount
        let titleRow = rowCount / 3
        let subtitleRow = rowCount * 11 / 20
        let buttonRow = rowCount - rowCount / 6

        // Logo positioning for component layer
        logoRow = max(1, titleRow - 8)

        // "LISTEN TO WHERE YOU ARE" centered at subtitleRow
        renderCenteredLine("LISTEN TO WHERE YOU ARE", into: grid, row: subtitleRow, color: .bold, bold: false)

        // "FOR THE LOVE OF MUSIC / COSTS NOTHING / COLLECTS NOTHING" centered between subtitle and button
        let taglineRow = subtitleRow + (buttonRow - subtitleRow) / 2 - 1
        let taglineLines = ["FOR THE LOVE OF MUSIC", "COSTS NOTHING", "COLLECTS NOTHING"]
        var row = taglineRow
        for line in taglineLines {
            guard row < grid.rowCount else { break }
            renderCenteredLine(line, into: grid, row: row, color: .bold, bold: true, small: true)
            row += 1
        }

        // [BEGIN] button
        renderButton(into: grid, row: buttonRow, label: "BEGIN")
    }

    // MARK: - Permission Screens

    private func renderPermission(into grid: CharacterGrid, glyph: Character, header: String,
                                  subtitle: String, buttonLabel: String) {
        let rowCount = grid.rowCount
        let titleRow = rowCount / 3
        let subtitleRow = rowCount * 11 / 20
        let buttonRow = rowCount - rowCount / 6

        // Glyph centered at titleRow - 1
        let glyphRow = titleRow - 1
        grid.setCell(
            layer: .content, row: glyphRow, col: cols / 2,
            state: CellState(character: glyph, color: .bold, bold: true)
        )

        // Header at titleRow
        renderCenteredLine(header, into: grid, row: titleRow, color: .bold, bold: true)

        // Subtitle at subtitleRow (may be multi-line with \n)
        let subtitleLines = subtitle.split(separator: "\n").map(String.init)
        var row = subtitleRow
        for line in subtitleLines {
            guard row < grid.rowCount else { break }
            renderCenteredLine(line, into: grid, row: row, color: .bold, bold: false)
            row += 1
        }

        // [READY] button
        renderButton(into: grid, row: buttonRow, label: buttonLabel)
    }

    // MARK: - Mic Denied

    private func renderMicDenied(into grid: CharacterGrid) {
        let rowCount = grid.rowCount
        let titleRow = rowCount / 3
        let subtitleRow = rowCount * 11 / 20
        let buttonRow = rowCount - rowCount / 6

        // Glyph
        let glyphRow = titleRow - 1
        grid.setCell(
            layer: .content, row: glyphRow, col: cols / 2,
            state: CellState(character: "\u{25C9}", color: .bold, bold: true)
        )

        // Header
        renderCenteredLine("MICROPHONE REQUIRED", into: grid, row: titleRow, color: .bold, bold: true)

        // Subtitle
        renderCenteredLine("OPEN SETTINGS TO ENABLE", into: grid, row: subtitleRow, color: .bold, bold: false)

        // [SETTINGS] button
        renderButton(into: grid, row: buttonRow, label: "SETTINGS")
    }

    // MARK: - Button Rendering

    private func renderButton(into grid: CharacterGrid, row: Int, label: String) {
        let buttonWidth = label.count + 4
        let buttonCol = max(0, (cols - buttonWidth) / 2)
        let size = BracketButton.render(
            into: grid, row: row, col: buttonCol,
            lines: [label], pressed: false
        )
        buttonRegion = (row: row, col: buttonCol, width: size.width, height: size.height)
    }

    /// Re-render the button in pressed state (double-line borders).
    func renderButtonPressed(into grid: CharacterGrid) {
        let region = buttonRegion
        guard region.width > 0 else { return }

        // Determine the label from the current step
        let label: String
        switch currentStep {
        case .welcome: label = "BEGIN"
        case .microphone:
            label = isMicDenied ? "SETTINGS" : "READY"
        case .location: label = "READY"
        case .speech: label = "READY"
        }

        BracketButton.render(
            into: grid, row: region.row, col: region.col,
            lines: [label], pressed: true
        )
    }

    // MARK: - Rendering Helpers

    private func renderCenteredLine(_ text: String, into grid: CharacterGrid, row: Int,
                                    color: GridColor, bold: Bool, small: Bool = false) {
        guard row < grid.rowCount else { return }
        let uppercased = text.uppercased()
        let startCol = max(0, (cols - uppercased.count) / 2)
        for (i, ch) in uppercased.enumerated() {
            guard startCol + i < cols else { break }
            grid.setCell(
                layer: .content, row: row, col: startCol + i,
                state: CellState(character: ch, color: color, bold: bold, small: small)
            )
        }
    }
}

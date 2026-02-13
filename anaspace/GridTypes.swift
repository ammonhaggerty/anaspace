import UIKit

// MARK: - Font Constants

enum FontName {
    static let regular = "JetBrainsMono-Regular"
    static let bold = "JetBrainsMono-Bold"
}

// MARK: - Grid Metrics

struct GridMetrics {
    static let fontSize: CGFloat = 15.52
    static let kern: CGFloat = fontSize * 0.11
    static let lineHeight: CGFloat = 22.3
    static let columns: Int = 33
    static let topPadding: CGFloat = 63
    static let bottomFooter: CGFloat = 97
    static let sideMargin: CGFloat = 16

    static var font: UIFont {
        UIFont(name: FontName.regular, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    static var boldFont: UIFont {
        UIFont(name: FontName.bold, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .bold)
    }

    static func rowCount(for availableHeight: CGFloat) -> Int {
        let gridHeight = availableHeight - topPadding - bottomFooter
        return max(1, Int(floor(gridHeight / lineHeight)))
    }
}

// MARK: - Grid Layer

enum GridLayer: Int, CaseIterable {
    case structure = 0
    case content = 1
    case transition = 2

    var zPosition: CGFloat {
        CGFloat(rawValue)
    }
}

// MARK: - Grid Color

enum GridColor {
    case background
    case structure
    case content
    case accent
    case navDark
    case clear

    var uiColor: UIColor {
        switch self {
        case .background: UIColor(red: 0.769, green: 0.686, blue: 0.627, alpha: 1) // #C4AFA0
        case .structure:  UIColor(red: 0.710, green: 0.631, blue: 0.573, alpha: 1) // #B5A192
        case .content:    UIColor(red: 0.165, green: 0.122, blue: 0.102, alpha: 1) // #2A1F1A
        case .accent:     UIColor(red: 0.878, green: 0.188, blue: 0.188, alpha: 1) // #E03030
        case .navDark:    UIColor(red: 0.118, green: 0.078, blue: 0.063, alpha: 1) // #1E1410
        case .clear:      .clear
        }
    }
}

// MARK: - Cell State

struct CellState: Equatable {
    var character: Character
    var color: GridColor
    var bold: Bool

    static let empty = CellState(character: " ", color: .clear, bold: false)
}

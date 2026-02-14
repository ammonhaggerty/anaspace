import UIKit

// MARK: - Font Constants

enum FontName {
    static let regular = "JetBrainsMono-Regular"
    static let bold = "JetBrainsMono-Bold"
}

// MARK: - Grid Metrics

struct GridMetrics {
    // Fixed constants
    static let columns: Int = 33
    static let topPadding: CGFloat = 63
    static let bottomFooter: CGFloat = 97
    static let sideMargin: CGFloat = 20

    // Kern as a proportion of font size
    private static let kernRatio: CGFloat = 0.11

    // Computed from screen width
    let fontSize: CGFloat
    let kern: CGFloat
    let lineHeight: CGFloat
    let cellWidth: CGFloat
    let font: UIFont
    let boldFont: UIFont

    init(screenWidth: CGFloat) {
        let availableWidth = screenWidth - 2 * Self.sideMargin

        // Measure font metrics at a reference size
        let refSize: CGFloat = 100
        let refFont = UIFont(name: FontName.regular, size: refSize)
            ?? .monospacedSystemFont(ofSize: refSize, weight: .regular)
        let charAdvance = NSAttributedString(
            string: "A", attributes: [.font: refFont]
        ).size().width
        let advanceRatio = charAdvance / refSize

        // Measure actual bounding box height of ░ glyph (not typographic ascent+descent)
        let characters: [UniChar] = [0x2591]
        var glyphs: [CGGlyph] = [0]
        CTFontGetGlyphsForCharacters(refFont as CTFont, characters, &glyphs, 1)
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(refFont as CTFont, .default, glyphs, &boundingRect, 1)
        let glyphHeightRatio = boundingRect.height / refSize

        // Solve: availableWidth = cols * (fontSize * advanceRatio) + (cols-1) * (fontSize * kernRatio)
        let cols = CGFloat(Self.columns)
        let multiplier = cols * advanceRatio + (cols - 1) * Self.kernRatio

        self.fontSize = availableWidth / multiplier
        self.kern = self.fontSize * Self.kernRatio
        // Line height = actual glyph height + kern, so vertical gap matches horizontal gap
        self.lineHeight = self.fontSize * glyphHeightRatio + self.kern
        self.cellWidth = availableWidth / cols
        self.font = UIFont(name: FontName.regular, size: self.fontSize)
            ?? .monospacedSystemFont(ofSize: self.fontSize, weight: .regular)
        self.boldFont = UIFont(name: FontName.bold, size: self.fontSize)
            ?? .monospacedSystemFont(ofSize: self.fontSize, weight: .bold)
    }

    func rowCount(for availableHeight: CGFloat) -> Int {
        let gridHeight = availableHeight - Self.topPadding
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
    case background  // #CBB4A5
    case tint        // #E4D7CE
    case bold        // #301818
    case highlight   // #FFFFFF
    case focus       // #FF0000
    case clear

    var uiColor: UIColor {
        switch self {
        case .background: UIColor(red: 0.796, green: 0.706, blue: 0.647, alpha: 1)
        case .tint:       UIColor(red: 0.894, green: 0.843, blue: 0.808, alpha: 1)
        case .bold:       UIColor(red: 0.188, green: 0.094, blue: 0.094, alpha: 1)
        case .highlight:  UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        case .focus:      UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1)
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

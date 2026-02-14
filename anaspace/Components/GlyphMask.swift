import UIKit

struct GlyphMask {
    private static var cachedImage: UIImage?
    private static var cachedKey: String?

    static func render(cols: Int, rows: Int, metrics: GridMetrics) -> UIImage {
        let key = "\(cols)x\(rows)@\(metrics.fontSize)"
        if let cachedImage, cachedKey == key {
            return cachedImage
        }

        let width = CGFloat(cols) * metrics.cellWidth
        let height = CGFloat(rows) * metrics.lineHeight

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height)
        )

        let image = renderer.image { ctx in
            let glyph = "\u{2593}" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: metrics.font,
                .foregroundColor: UIColor.white,
                .kern: metrics.kern
            ]

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * metrics.cellWidth
                    let y = CGFloat(row) * metrics.lineHeight
                    glyph.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
                }
            }
        }

        cachedImage = image
        cachedKey = key
        return image
    }
}

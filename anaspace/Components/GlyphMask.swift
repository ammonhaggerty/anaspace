import UIKit

struct GlyphMask {
    private static var cache: [String: UIImage] = [:]

    static func render(cols: Int, rows: Int, metrics: GridMetrics) -> UIImage {
        let key = "\(cols)x\(rows)@\(metrics.fontSize)"
        if let cached = cache[key] {
            return cached
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

        cache[key] = image
        return image
    }
}

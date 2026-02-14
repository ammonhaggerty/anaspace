import SwiftUI

struct BeveledShape: Shape {
    let bevel: CGFloat

    func path(in rect: CGRect) -> Path {
        let b = min(bevel, min(rect.width, rect.height) / 2)

        var path = Path()
        path.move(to: CGPoint(x: b, y: 0))
        path.addLine(to: CGPoint(x: rect.width - b, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: b))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - b))
        path.addLine(to: CGPoint(x: rect.width - b, y: rect.height))
        path.addLine(to: CGPoint(x: b, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height - b))
        path.addLine(to: CGPoint(x: 0, y: b))
        path.closeSubpath()

        return path
    }
}

import SwiftUI
import CoreLocation

struct MapLabelOverlay: View {
    let labels: [MapLabel]
    let metrics: GridMetrics
    var onLabelTap: ((CLLocationCoordinate2D) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ForEach(labels) { label in
                HStack(spacing: 0) {
                    ForEach(Array(label.name.enumerated()), id: \.offset) { _, ch in
                        Text(String(ch))
                            .font(Font(metrics.font))
                            .foregroundStyle(GridColor.highlight.uiColor.swiftUI)
                            .frame(width: metrics.cellWidth, height: metrics.lineHeight)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onLabelTap?(CLLocationCoordinate2D(
                        latitude: label.latitude,
                        longitude: label.longitude
                    ))
                }
                .offset(
                    x: CGFloat(label.col) * metrics.cellWidth,
                    y: CGFloat(label.row) * metrics.lineHeight
                )
            }
        }
    }
}

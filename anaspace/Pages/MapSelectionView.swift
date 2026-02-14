import SwiftUI
import CoreLocation

struct MapSelectionView: View {
    let initialCoordinate: CLLocationCoordinate2D
    let onLocationSelected: (CLLocationCoordinate2D) -> Void
    let onDismiss: () -> Void

    @State private var mapController = MapInteractionController()

    private let navDark = GridColor.bold.uiColor.swiftUI
    private let navFg = GridColor.background.uiColor.swiftUI

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(screenWidth: geo.size.width)
            let cols = GridMetrics.columns
            let gridWidth = CGFloat(cols) * metrics.cellWidth
            let mapTop = GridMetrics.topPadding
            let mapBottom = GridMetrics.bottomFooter
            let mapHeight = geo.size.height - mapTop - mapBottom
            let rows = Int(floor(mapHeight / metrics.lineHeight))
            let clampedHeight = CGFloat(rows) * metrics.lineHeight
            let mask = GlyphMask.render(cols: cols, rows: rows, metrics: metrics)

            ZStack(alignment: .topLeading) {
                GridColor.background.uiColor.swiftUI
                    .ignoresSafeArea()

                // Map in grid area
                InteractiveMapDisplay(
                    coordinate: initialCoordinate,
                    zoom: 4,
                    controller: mapController,
                    onTap: { coordinate in
                        onLocationSelected(coordinate)
                    }
                )
                .frame(width: gridWidth, height: clampedHeight)
                .mask(
                    Image(uiImage: mask)
                        .resizable()
                        .frame(width: gridWidth, height: clampedHeight)
                )
                .blendMode(.multiply)
                .position(
                    x: GridMetrics.sideMargin + gridWidth / 2,
                    y: mapTop + clampedHeight / 2
                )

                // Bottom nav bar
                HStack {
                    NavButton(iconName: "icon-back", fg: navFg, bg: navDark, onTap: onDismiss)

                    Spacer()

                    NavButton(iconName: "icon-zoom-out", fg: navFg, bg: navDark) {
                        mapController.zoomOut()
                    }
                    NavButton(iconName: "icon-zoom-in", fg: navFg, bg: navDark) {
                        mapController.zoomIn()
                    }
                }
                .padding(.horizontal, 40)
                .frame(width: geo.size.width, height: mapBottom)
                .position(
                    x: geo.size.width / 2,
                    y: geo.size.height - mapBottom / 2
                )
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }
}

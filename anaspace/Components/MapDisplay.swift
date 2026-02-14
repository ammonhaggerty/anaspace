import SwiftUI
import MapboxMaps

struct MapDisplay: UIViewRepresentable {
    let metrics: GridMetrics
    let coordinate: CLLocationCoordinate2D
    let zoom: Double

    func makeUIView(context: Context) -> MapView {
        let camera = CameraOptions(
            center: coordinate,
            zoom: CGFloat(zoom)
        )
        let styleURI = StyleURI(rawValue: "mapbox://styles/ammonhaggerty/cmljp0l04001e01sshu4fdiw1")!
        let options = MapInitOptions(
            cameraOptions: camera,
            styleURI: styleURI
        )
        let mapView = MapView(frame: .zero, mapInitOptions: options)
        mapView.backgroundColor = .clear
        mapView.isUserInteractionEnabled = false

        // Hide Mapbox UI elements
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        // Hide logo and attribution by finding their views
        DispatchQueue.main.async {
            for subview in mapView.subviews {
                if subview is UIButton || String(describing: type(of: subview)).contains("Logo") {
                    subview.isHidden = true
                }
                for child in subview.subviews {
                    if child is UIButton || child is UIImageView {
                        child.isHidden = true
                    }
                }
            }
        }

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {}
}

import SwiftUI
import MapboxMaps

@Observable @MainActor
final class MapInteractionController {
    weak var mapView: MapView?

    func zoomIn() {
        guard let mapView else { return }
        let current = mapView.mapboxMap.cameraState.zoom
        mapView.mapboxMap.setCamera(to: CameraOptions(zoom: min(current + 1, 18)))
    }

    func zoomOut() {
        guard let mapView else { return }
        let current = mapView.mapboxMap.cameraState.zoom
        mapView.mapboxMap.setCamera(to: CameraOptions(zoom: max(current - 1, 1)))
    }
}

struct InteractiveMapDisplay: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let zoom: Double
    let controller: MapInteractionController
    var onTap: ((CLLocationCoordinate2D) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

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

        // Enable pan and pinch zoom only
        mapView.gestures.options.panEnabled = true
        mapView.gestures.options.pinchEnabled = true
        mapView.gestures.options.pinchZoomEnabled = true
        mapView.gestures.options.pinchPanEnabled = true
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.doubleTapToZoomInEnabled = false
        mapView.gestures.options.doubleTouchToZoomOutEnabled = false
        mapView.gestures.options.quickZoomEnabled = false

        // Hide UI elements
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.scaleBar.visibility = .hidden

        // Hide logo/attribution
        DispatchQueue.main.async {
            self.hideOrnamentViews(in: mapView)
        }

        // Tap gesture for location selection
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)

        // Give controller a reference
        controller.mapView = mapView
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        context.coordinator.onTap = onTap
    }

    private func hideOrnamentViews(in mapView: MapView) {
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

    class Coordinator: NSObject {
        var onTap: ((CLLocationCoordinate2D) -> Void)?
        weak var mapView: MapView?

        init(onTap: ((CLLocationCoordinate2D) -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            onTap?(coordinate)
        }
    }
}

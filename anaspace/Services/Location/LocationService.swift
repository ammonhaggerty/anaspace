import CoreLocation

// MARK: - Location Service

@Observable
@MainActor
final class LocationService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = true
    private(set) var currentResult: LocationResult?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var delegate: LocationServiceDelegate?

    // MARK: - ObservationService Conformance

    func activate() async throws {
        let coordinate = try await requestSingleLocation()
        currentResult = await reverseGeocode(coordinate)
    }

    func deactivate() {
        manager.stopUpdatingLocation()
        // Resume any pending continuation before clearing callbacks
        delegate?.cancelPending()
        delegate = nil
    }

    // MARK: - Public Methods

    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> LocationResult? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }

        return LocationResult(
            coordinate: coordinate,
            placeName: placemark.name,
            neighborhood: placemark.subLocality,
            city: placemark.locality,
            state: placemark.administrativeArea,
            country: placemark.country,
            isoCountryCode: placemark.isoCountryCode
        )
    }

    static func displayLabel(for result: LocationResult) -> String {
        let city = result.city ?? result.placeName ?? "UNKNOWN"
        let state = result.state ?? ""
        let country = result.isoCountryCode ?? ""

        if state.isEmpty {
            return "\(city) | \(country)".uppercased()
        } else {
            return "\(city), \(state) | \(country)".uppercased()
        }
    }

    // MARK: - Private Helpers

    private func requestSingleLocation() async throws -> CLLocationCoordinate2D {
        let serviceDelegate = LocationServiceDelegate()
        delegate = serviceDelegate
        manager.delegate = serviceDelegate

        return try await withCheckedThrowingContinuation { continuation in
            serviceDelegate.onLocation = { location in
                continuation.resume(returning: location.coordinate)
            }
            serviceDelegate.onError = { error in
                continuation.resume(throwing: error)
            }
            manager.requestLocation()
        }
    }
}

// MARK: - Location Service Delegate

private final class LocationServiceDelegate: NSObject, CLLocationManagerDelegate {

    var onLocation: ((CLLocation) -> Void)?
    var onError: ((Error) -> Void)?

    /// Resume any pending continuation with a cancellation error, preventing leaks.
    func cancelPending() {
        let error = onError
        onLocation = nil
        onError = nil
        error?(CancellationError())
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocation?(location)
        onLocation = nil
        onError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error)
        onLocation = nil
        onError = nil
    }
}

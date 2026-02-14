import MapboxMaps
import UIKit

enum MapLabelKind {
    case city, state, country, water
}

struct MapLabel: Identifiable {
    let id: String        // "NAME@lat,lon" dedupe key
    let name: String      // uppercase display text
    let row: Int          // grid row
    let col: Int          // grid col (left edge of label)
    let length: Int       // character count
    let importance: Int   // lower = more important
    let latitude: Double
    let longitude: Double
    let kind: MapLabelKind
    let countryCode: String?  // iso_3166_1 (e.g. "UA", "GR")
    let stateCode: String?    // iso_3166_2 (e.g. "US-CA")
}

extension MapLabel: Equatable {
    static func == (lhs: MapLabel, rhs: MapLabel) -> Bool {
        lhs.id == rhs.id && lhs.row == rhs.row && lhs.col == rhs.col
    }
}

@Observable @MainActor
final class MapLabelProvider {
    var labels: [MapLabel] = []
    var isMoving = false

    private var allCities: [MapLabel] = []
    private weak var mapView: MapView?
    private var cameraCancelable: AnyCancelable?
    private var idleCancelable: AnyCancelable?
    private var styleLoadedCancelable: AnyCancelable?
    private var queryTask: Task<Void, Never>?
    private var vectorSourceId: String?

    private let rows: Int
    private let cols: Int
    private let cellWidth: CGFloat
    private let lineHeight: CGFloat

    private let sourceLayerIds = [
        "place_label",
        "country_label",
        "state_label",
        "natural_label",
        "water_label",
        "marine_label"
    ]

    init(rows: Int, cols: Int, cellWidth: CGFloat, lineHeight: CGFloat) {
        self.rows = rows
        self.cols = cols
        self.cellWidth = cellWidth
        self.lineHeight = lineHeight
    }

    func attach(to mapView: MapView) {
        self.mapView = mapView

        // Try immediately in case style is already loaded
        discoverVectorSource()

        // Subscribe to style loaded for async style loading
        styleLoadedCancelable = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            Task { @MainActor in
                self?.discoverVectorSource()
                self?.scheduleQuery()
            }
        }

        cameraCancelable = mapView.mapboxMap.onCameraChanged.observe { [weak self] _ in
            Task { @MainActor in
                self?.isMoving = true
                self?.scheduleQuery()
            }
        }

        idleCancelable = mapView.mapboxMap.onMapIdle.observe { [weak self] _ in
            Task { @MainActor in
                self?.scheduleQuery()
                self?.isMoving = false
            }
        }
    }

    func detach() {
        cameraCancelable?.cancel()
        idleCancelable?.cancel()
        styleLoadedCancelable?.cancel()
        queryTask?.cancel()
        cameraCancelable = nil
        idleCancelable = nil
        styleLoadedCancelable = nil
        queryTask = nil
        mapView = nil
    }

    // MARK: - Selection

    func coordinateForSelection(_ label: MapLabel) -> CLLocationCoordinate2D? {
        switch label.kind {
        case .city:
            return CLLocationCoordinate2D(latitude: label.latitude, longitude: label.longitude)
        case .country:
            return mostProminentCity(forCountry: label.countryCode, fallback: label)
        case .state:
            return mostProminentCity(forState: label.stateCode, fallbackCountry: label.countryCode, fallback: label)
        case .water:
            return nil
        }
    }

    private func mostProminentCity(forCountry code: String?, fallback label: MapLabel) -> CLLocationCoordinate2D? {
        if let code, !code.isEmpty {
            let matches = allCities.filter { $0.countryCode == code }
            if let best = matches.min(by: { $0.importance < $1.importance }) {
                return CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
            }
        }
        // Fallback: nearest prominent city within radius
        return nearestProminentCity(near: label, searchRadius: 20)
    }

    private func mostProminentCity(forState code: String?, fallbackCountry: String?, fallback label: MapLabel) -> CLLocationCoordinate2D? {
        if let code, !code.isEmpty {
            let matches = allCities.filter { $0.stateCode == code }
            if let best = matches.min(by: { $0.importance < $1.importance }) {
                return CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
            }
        }
        // Fallback: most prominent city in same country within radius
        if let country = fallbackCountry, !country.isEmpty {
            let matches = allCities.filter { city in
                guard city.countryCode == country else { return false }
                let dlat = city.latitude - label.latitude
                let dlon = city.longitude - label.longitude
                return sqrt(dlat * dlat + dlon * dlon) < 8
            }
            if let best = matches.min(by: { $0.importance < $1.importance }) {
                return CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
            }
        }
        return nearestProminentCity(near: label, searchRadius: 8)
    }

    private func nearestProminentCity(near label: MapLabel, searchRadius: Double) -> CLLocationCoordinate2D {
        let candidates = allCities.filter { city in
            let dlat = city.latitude - label.latitude
            let dlon = city.longitude - label.longitude
            return sqrt(dlat * dlat + dlon * dlon) < searchRadius
        }
        guard let best = candidates.min(by: { $0.importance < $1.importance }) else {
            return CLLocationCoordinate2D(latitude: label.latitude, longitude: label.longitude)
        }
        return CLLocationCoordinate2D(latitude: best.latitude, longitude: best.longitude)
    }

    // MARK: - Source Discovery

    private func discoverVectorSource() {
        guard let mapView else { return }
        let sources = mapView.mapboxMap.allSourceIdentifiers
        vectorSourceId = sources.first(where: { $0.type == .vector })?.id
    }

    // MARK: - Query Scheduling

    private func scheduleQuery() {
        queryTask?.cancel()
        queryTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await executeQuery()
        }
    }

    private func executeQuery() async {
        guard let mapView else { return }

        // Re-discover source if not yet found
        if vectorSourceId == nil { discoverVectorSource() }
        guard let sourceId = vectorSourceId else { return }

        let options = SourceQueryOptions(sourceLayerIds: sourceLayerIds, filter: NSNull())

        let features: [QueriedSourceFeature]
        do {
            features = try await withCheckedThrowingContinuation { continuation in
                mapView.mapboxMap.querySourceFeatures(
                    for: sourceId,
                    options: options
                ) { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        let processed = processFeatures(features, mapView: mapView)
        allCities = processed.filter { $0.kind == .city }
        labels = resolveOverlaps(processed)
    }

    // MARK: - Feature Processing

    private func processFeatures(_ features: [QueriedSourceFeature], mapView: MapView) -> [MapLabel] {
        var result: [MapLabel] = []
        var seen = Set<String>()
        let viewBounds = mapView.bounds

        for qrf in features {
            let feature = qrf.queriedFeature.feature
            let sourceLayer = qrf.queriedFeature.sourceLayer ?? ""
            guard let properties = feature.properties else { continue }

            // Extract name
            let name: String
            if let n = stringProperty(properties, key: "name_en") {
                name = n
            } else if let n = stringProperty(properties, key: "name") {
                name = n
            } else {
                continue
            }
            guard !name.isEmpty else { continue }

            // Extract symbolrank and ISO codes
            let symbolrank = intProperty(properties, key: "symbolrank") ?? 10
            let countryCode = stringProperty(properties, key: "iso_3166_1")
            let stateCode = stringProperty(properties, key: "iso_3166_2")

            // Categorize by source layer and feature class
            let featureClass = stringProperty(properties, key: "class") ?? ""
            let importance: Int
            let kind: MapLabelKind
            if sourceLayer.contains("country") || featureClass == "country" {
                importance = 1
                kind = .country
            } else if sourceLayer.contains("state") || featureClass == "state" || featureClass == "province" {
                importance = 2
                kind = .state
            } else if sourceLayer.contains("natural") || sourceLayer.contains("water") || sourceLayer.contains("marine") {
                importance = 3 + symbolrank
                kind = .water
            } else {
                // place_label (settlements)
                guard symbolrank <= 12 else { continue }
                importance = symbolrank
                kind = .city
            }

            // Get coordinate from geometry
            guard case .point(let point) = feature.geometry else { continue }
            let coordinate = point.coordinates

            // Deduplicate
            let key = "\(name)@\(Int(coordinate.latitude * 100)),\(Int(coordinate.longitude * 100))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            // Convert to screen point and filter to viewport
            let screenPoint = mapView.mapboxMap.point(for: coordinate)
            guard viewBounds.contains(screenPoint) else { continue }

            // Convert screen point to grid position
            let row = Int(floor(screenPoint.y / lineHeight))
            let displayName = name.uppercased()
            let length = displayName.count
            let anchorCol = Int(floor(screenPoint.x / cellWidth))
            let col = anchorCol - length / 2

            guard row >= 0, row < rows, col >= 0, col + length <= cols else { continue }

            result.append(MapLabel(
                id: key,
                name: displayName,
                row: row,
                col: col,
                length: length,
                importance: importance,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                kind: kind,
                countryCode: countryCode,
                stateCode: stateCode
            ))
        }

        return result
    }

    // MARK: - Overlap Resolution

    private func resolveOverlaps(_ labels: [MapLabel]) -> [MapLabel] {
        let sorted = labels.sorted { $0.importance < $1.importance }
        var occupied = Array(repeating: Array(repeating: false, count: cols), count: rows)
        var result: [MapLabel] = []

        for label in sorted {
            let minR = max(0, label.row - 1)
            let maxR = min(rows - 1, label.row + 1)
            let minC = max(0, label.col - 1)
            let maxC = min(cols - 1, label.col + label.length)

            var overlaps = false
            for r in minR...maxR {
                for c in minC...maxC {
                    if occupied[r][c] { overlaps = true; break }
                }
                if overlaps { break }
            }
            guard !overlaps else { continue }

            for c in label.col..<(label.col + label.length) where c >= 0 && c < cols {
                occupied[label.row][c] = true
            }

            result.append(label)
        }

        return result
    }

    // MARK: - JSON Helpers

    private func stringProperty(_ properties: JSONObject, key: String) -> String? {
        guard let wrapper = properties[key], let value = wrapper else { return nil }
        if case .string(let s) = value { return s }
        return nil
    }

    private func intProperty(_ properties: JSONObject, key: String) -> Int? {
        guard let wrapper = properties[key], let value = wrapper else { return nil }
        if case .number(let n) = value { return Int(n) }
        return nil
    }
}

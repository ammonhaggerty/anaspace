import Foundation
import MusicKit

// MARK: - Music Service

@Observable
@MainActor
final class MusicService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = false
    var isAuthorized: Bool { MusicAuthorization.currentStatus == .authorized }

    // MARK: - ObservationService Conformance

    func activate() async throws {
        isAvailable = true
    }

    func deactivate() {
        isAvailable = false
    }

    // MARK: - Enrichment

    /// Enrich a Shazam result with MusicKit catalog data
    func enrich(shazamResult: ShazamResult) async -> MusicEnrichment? {
        // Catalog search works without subscription (just needs authorization)
        guard isAuthorized else { return nil }

        do {
            var request = MusicCatalogSearchRequest(
                term: "\(shazamResult.artist) \(shazamResult.title)",
                types: [Song.self, Artist.self]
            )
            request.limit = 5

            let response = try await request.response()

            let song = response.songs.first
            let artist = response.artists.first

            return MusicEnrichment(
                genre: song?.genreNames.first,
                allGenres: song?.genreNames ?? [],
                editorialNotes: artist?.editorialNotes?.standard,
                releaseDate: song?.releaseDate,
                appleMusicURL: song?.url,
                artistURL: artist?.url
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Enrichment Data

struct MusicEnrichment: Sendable {
    let genre: String?
    let allGenres: [String]
    let editorialNotes: String?
    let releaseDate: Date?
    let appleMusicURL: URL?
    let artistURL: URL?
}

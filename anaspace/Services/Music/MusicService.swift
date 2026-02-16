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
    // MARK: - Catalog Search for Previews

    /// Search for songs by an artist near a given year, returning tracks with preview URLs.
    func searchSongs(artist: String, near year: Int, limit: Int = 5) async -> [TrackInfo] {
        guard isAuthorized else { return [] }

        do {
            var request = MusicCatalogSearchRequest(term: artist, types: [Song.self])
            request.limit = 25

            let response = try await request.response()

            let tracks: [TrackInfo] = response.songs.compactMap { song in
                guard let previewURL = song.previewAssets?.first?.url else { return nil }
                let songYear = song.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
                return TrackInfo(
                    artist: song.artistName,
                    title: song.title,
                    year: songYear,
                    previewURL: previewURL
                )
            }

            // Sort by proximity to target year
            let sorted = tracks.sorted { abs($0.year - year) < abs($1.year - year) }
            return Array(sorted.prefix(limit))
        } catch {
            return []
        }
    }

    /// Look up a specific song by Apple Music ID and return its preview info.
    func getSongByID(_ appleMusicID: String) async -> TrackInfo? {
        guard isAuthorized else { return nil }

        do {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
            let response = try await request.response()

            guard let song = response.items.first,
                  let previewURL = song.previewAssets?.first?.url else { return nil }

            let songYear = song.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
            return TrackInfo(
                artist: song.artistName,
                title: song.title,
                year: songYear,
                previewURL: previewURL
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

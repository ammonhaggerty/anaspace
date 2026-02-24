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

    /// Discover a prominent artist associated with a location by searching the MusicKit catalog.
    /// Returns the top artist name, or nil if unavailable.
    func discoverArtist(near location: String) async -> String? {
        guard isAuthorized else { return nil }

        do {
            var request = MusicCatalogSearchRequest(term: location, types: [Artist.self])
            request.limit = 5

            let response = try await request.response()
            guard let artist = response.artists.first else { return nil }

            print("[MusicKit] Discovered artist for \(location): \(artist.name)")
            return artist.name
        } catch {
            print("[MusicKit] Artist discovery failed: \(error)")
            return nil
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
    // MARK: - Song + Album Lookup

    /// Find a specific song by title and artist, returning the track and other songs from its album.
    func findSongWithAlbum(title: String, artist: String) async -> (song: TrackInfo, albumTracks: [TrackInfo])? {
        guard isAuthorized else { return nil }

        do {
            var request = MusicCatalogSearchRequest(term: "\(artist) \(title)", types: [Song.self])
            request.limit = 10

            let response = try await request.response()

            // Find best match — artist name should be close
            let artistLower = artist.lowercased()
            let titleLower = title.lowercased()
            guard let song = response.songs.first(where: {
                $0.artistName.lowercased().contains(artistLower) ||
                artistLower.contains($0.artistName.lowercased())
            }) ?? response.songs.first(where: {
                $0.title.lowercased().contains(titleLower)
            }) else { return nil }

            guard let previewURL = song.previewAssets?.first?.url else { return nil }

            let songYear = song.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
            let track = TrackInfo(artist: song.artistName, title: song.title, year: songYear, previewURL: previewURL)

            // Fetch album tracks
            let albumTracks = await getAlbumTracks(for: song)
            return (song: track, albumTracks: albumTracks)
        } catch {
            return nil
        }
    }

    /// Get all playable tracks from a song's album.
    private func getAlbumTracks(for song: Song) async -> [TrackInfo] {
        do {
            let detailed = try await song.with(.albums)
            guard let album = detailed.albums?.first else { return [] }
            let detailedAlbum = try await album.with(.tracks)
            guard let tracks = detailedAlbum.tracks else { return [] }

            return tracks.compactMap { track -> TrackInfo? in
                guard let previewURL = track.previewAssets?.first?.url else { return nil }
                let year = track.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
                return TrackInfo(artist: track.artistName, title: track.title, year: year, previewURL: previewURL)
            }
        } catch {
            return []
        }
    }

    /// Find the album closest to a year for an artist, returning tracks sorted by popularity.
    func getAlbumTracksNearYear(artist: String, year: Int) async -> [TrackInfo] {
        guard isAuthorized else { return [] }

        do {
            // Get artist's top songs for popularity ranking
            var artistRequest = MusicCatalogSearchRequest(term: artist, types: [Artist.self])
            artistRequest.limit = 3
            let artistResponse = try await artistRequest.response()
            let topSongTitles: Set<String>
            if let matchedArtist = artistResponse.artists.first {
                let detailed = try await matchedArtist.with(.topSongs)
                topSongTitles = Set((detailed.topSongs ?? []).map { $0.title.lowercased() })
            } else {
                topSongTitles = []
            }

            // Search for albums by artist
            var albumRequest = MusicCatalogSearchRequest(term: artist, types: [Album.self])
            albumRequest.limit = 25
            let albumResponse = try await albumRequest.response()

            // Filter to artist's albums and sort by year proximity
            let artistLower = artist.lowercased()
            let albums = albumResponse.albums
                .filter { $0.artistName.lowercased().contains(artistLower) || artistLower.contains($0.artistName.lowercased()) }
                .sorted { a, b in
                    let yearA = a.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
                    let yearB = b.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
                    return abs(yearA - year) < abs(yearB - year)
                }

            guard let closestAlbum = albums.first else { return [] }

            let detailedAlbum = try await closestAlbum.with(.tracks)
            guard let tracks = detailedAlbum.tracks else { return [] }

            let trackInfos: [TrackInfo] = tracks.compactMap { track -> TrackInfo? in
                guard let previewURL = track.previewAssets?.first?.url else { return nil }
                let songYear = track.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
                return TrackInfo(artist: track.artistName, title: track.title, year: songYear, previewURL: previewURL)
            }

            // Sort: top songs first, then album order
            return trackInfos.sorted { a, b in
                let aIsTop = topSongTitles.contains(a.title.lowercased())
                let bIsTop = topSongTitles.contains(b.title.lowercased())
                if aIsTop != bIsTop { return aIsTop }
                return false // preserve relative order
            }
        } catch {
            return []
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

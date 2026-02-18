import Foundation

@MainActor
final class MusicQueueBuilder {
    private let music: MusicService

    init(music: MusicService) {
        self.music = music
    }

    // MARK: - General Queue (Home/Subject Page)

    /// Build a mixed queue from a ClaudeResult using Claude's recommended songs per connection.
    ///
    /// Priority order:
    /// 1. Initial song (from Shazam appleMusicID if available)
    /// 2. Subject artist — album tracks near the year
    /// 3. Each artist connection — Claude's recommended song (fallback: song near year)
    /// 4. More from subject artist near the year
    private static let artistSubjectTypes: Set<String> = [
        "artist", "band", "poet", "composer", "dj", "producer", "singer", "rapper", "musician"
    ]

    func buildQueue(
        from result: ClaudeResult,
        shazamResult: ShazamResult?,
        year: Int
    ) -> AsyncStream<TrackInfo> {
        let subjectIsArtist = Self.artistSubjectTypes.contains(result.subjectType.lowercased())

        return AsyncStream { continuation in
            Task { @MainActor in
                var seen = Set<String>()

                func yield(_ track: TrackInfo) {
                    let key = "\(track.artist)|\(track.title)".lowercased()
                    guard !seen.contains(key) else { return }
                    seen.insert(key)
                    continuation.yield(track)
                }

                // 1. Shazam match — direct ID lookup
                if let appleMusicID = shazamResult?.appleMusicID,
                   let track = await self.music.getSongByID(appleMusicID) {
                    yield(track)
                }

                if subjectIsArtist {
                    // 2. Subject artist — songs near the year
                    let subjectTracks = await self.music.searchSongs(artist: result.subject, near: year, limit: 2)
                    for track in subjectTracks {
                        yield(track)
                    }

                    // 3. Each artist connection — use Claude's recommended song
                    let artistConnections = result.connections.filter { $0.entityType.hasArtistCatalog }
                    for conn in artistConnections {
                        if let songTitle = conn.recommendedSong,
                           let found = await self.music.findSongWithAlbum(title: songTitle, artist: conn.name) {
                            yield(found.song)
                        } else {
                            let tracks = await self.music.searchSongs(artist: conn.name, near: year, limit: 1)
                            for track in tracks { yield(track) }
                        }
                    }

                    // 4. More from subject artist
                    let moreTracks = await self.music.searchSongs(artist: result.subject, near: year, limit: 5)
                    for track in moreTracks {
                        yield(track)
                    }
                } else {
                    // Non-artist subject: use keyArtists for a curated playlist near the year
                    let artists = result.keyArtists.isEmpty
                        ? result.connections.filter { $0.entityType.hasArtistCatalog }.map(\.name)
                        : result.keyArtists

                    // First pass: 2 tracks per key artist near the year
                    for artist in artists {
                        let tracks = await self.music.searchSongs(artist: artist, near: year, limit: 2)
                        for track in tracks { yield(track) }
                    }

                    // Second pass: backfill with more from each artist
                    for artist in artists.prefix(3) {
                        let tracks = await self.music.searchSongs(artist: artist, near: year, limit: 3)
                        for track in tracks { yield(track) }
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Entity Queue (Entity Page)

    /// Build a queue for a specific connection entity.
    ///
    /// Strategy:
    /// 1. Play Claude's recommended song first (if found)
    /// 2. Then play other tracks from the same album
    /// 3. Fallback: find the album closest to the year, play tracks by popularity
    func buildEntityQueue(connection: CultureConnection, year: Int) -> AsyncStream<TrackInfo> {
        AsyncStream { continuation in
            Task { @MainActor in
                var seen = Set<String>()

                func yield(_ track: TrackInfo) {
                    let key = "\(track.artist)|\(track.title)".lowercased()
                    guard !seen.contains(key) else { return }
                    seen.insert(key)
                    continuation.yield(track)
                }

                // Try Claude's recommended song first
                if let songTitle = connection.recommendedSong,
                   let found = await music.findSongWithAlbum(title: songTitle, artist: connection.name) {
                    // Recommended song plays first
                    yield(found.song)
                    // Then other album tracks
                    for track in found.albumTracks {
                        yield(track)
                    }
                } else {
                    // Fallback: closest album by year, sorted by popularity
                    let tracks = await music.getAlbumTracksNearYear(artist: connection.name, year: year)
                    for track in tracks {
                        yield(track)
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Creation Queue

    /// Build a queue starting with a specific song (for creation entities).
    func buildCreationQueue(songTitle: String, artist: String, year: Int) -> AsyncStream<TrackInfo> {
        AsyncStream { continuation in
            Task { @MainActor in
                var seen = Set<String>()

                func yield(_ track: TrackInfo) {
                    let key = "\(track.artist)|\(track.title)".lowercased()
                    guard !seen.contains(key) else { return }
                    seen.insert(key)
                    continuation.yield(track)
                }

                // Try to find the specific song and its album
                if let found = await music.findSongWithAlbum(title: songTitle, artist: artist) {
                    yield(found.song)
                    for track in found.albumTracks {
                        yield(track)
                    }
                } else {
                    // Fallback: search by title as general term
                    let tracks = await music.searchSongs(artist: "\(artist) \(songTitle)", near: year, limit: 10)
                    for track in tracks {
                        yield(track)
                    }
                }

                continuation.finish()
            }
        }
    }
}

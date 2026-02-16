import Foundation

@MainActor
final class MusicQueueBuilder {
    private let music: MusicService

    init(music: MusicService) {
        self.music = music
    }

    /// Build an ordered queue from a ClaudeResult, yielding tracks as they're found.
    ///
    /// Priority order:
    /// 1. Initial song (from Shazam appleMusicID if available)
    /// 2. Subject artist's popular song near the year
    /// 3. Influences and followers — their popular songs
    /// 4. Collaborators and peers — songs near the year
    /// 5. More songs from the subject artist
    func buildQueue(
        from result: ClaudeResult,
        shazamResult: ShazamResult?,
        year: Int
    ) -> AsyncStream<TrackInfo> {
        AsyncStream { continuation in
            Task { @MainActor in
                var seen = Set<String>()

                // Helper to yield unique tracks
                func yield(_ track: TrackInfo) {
                    let key = "\(track.artist)|\(track.title)".lowercased()
                    guard !seen.contains(key) else { return }
                    seen.insert(key)
                    continuation.yield(track)
                }

                // 1. Shazam match — direct ID lookup
                if let appleMusicID = shazamResult?.appleMusicID,
                   let track = await music.getSongByID(appleMusicID) {
                    yield(track)
                }

                // 2. Subject artist's song near the year
                let subjectTracks = await music.searchSongs(artist: result.subject, near: year, limit: 2)
                for track in subjectTracks {
                    yield(track)
                }

                // Categorize connections
                var influences: [CultureConnection] = []
                var followers: [CultureConnection] = []
                var collaborators: [CultureConnection] = []
                var peers: [CultureConnection] = []

                for conn in result.connections {
                    switch conn.entityType {
                    case .influence: influences.append(conn)
                    case .follower: followers.append(conn)
                    case .collaborator: collaborators.append(conn)
                    case .peer: peers.append(conn)
                    default: break
                    }
                }

                // 3. Influences and followers — popular songs (any era)
                for conn in (influences + followers).prefix(4) {
                    let tracks = await music.searchSongs(artist: conn.name, near: year, limit: 1)
                    for track in tracks { yield(track) }
                }

                // 4. Collaborators and peers — songs near the year
                for conn in (collaborators + peers).prefix(4) {
                    let tracks = await music.searchSongs(artist: conn.name, near: year, limit: 1)
                    for track in tracks { yield(track) }
                }

                // 5. More from subject artist
                let moreTracks = await music.searchSongs(artist: result.subject, near: year, limit: 5)
                for track in moreTracks {
                    yield(track)
                }

                continuation.finish()
            }
        }
    }
}

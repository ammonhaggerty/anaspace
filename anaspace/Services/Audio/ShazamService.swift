import AVFoundation
import MusicKit
import ShazamKit

// MARK: - Shazam Service

@Observable
@MainActor
final class ShazamService: ObservationService {

    // MARK: - Properties

    private(set) var isAvailable: Bool = true
    private(set) var result: ShazamResult?
    private(set) var isMatching = false

    private var session: SHManagedSession?
    private var matchTask: Task<Void, Never>?

    weak var audioService: AudioService?

    // MARK: - ObservationService Conformance

    func activate() async throws {
        result = nil
        isMatching = true

        let managedSession = SHManagedSession()
        session = managedSession

        matchTask = Task { [weak self] in
            let matchResult = await managedSession.result()

            guard let self, !Task.isCancelled else { return }

            switch matchResult {
            case .match(let match):
                guard let item = match.mediaItems.first else {
                    self.result = nil
                    self.isMatching = false
                    return
                }

                let album = self.extractAlbum(from: item)
                let releaseYear = self.extractReleaseYear(from: item)

                self.result = ShazamResult(
                    title: item.title ?? "Unknown",
                    artist: item.artist ?? "Unknown",
                    album: album,
                    appleMusicID: item.appleMusicID,
                    genres: item.genres,
                    releaseYear: releaseYear,
                    artworkURL: item.artworkURL,
                    confidence: 1.0
                )

            case .noMatch:
                self.result = nil

            case .error:
                self.result = nil

            @unknown default:
                self.result = nil
            }

            self.isMatching = false
        }
    }

    func deactivate() {
        matchTask?.cancel()
        matchTask = nil

        session?.cancel()
        session = nil

        isMatching = false
    }

    // MARK: - Private Helpers

    private func extractAlbum(from item: SHMatchedMediaItem) -> String? {
        if let song = item.songs.first {
            return song.albumTitle
        }
        return nil
    }

    private func extractReleaseYear(from item: SHMatchedMediaItem) -> Int? {
        if let song = item.songs.first, let releaseDate = song.releaseDate {
            return Calendar.current.component(.year, from: releaseDate)
        }
        return nil
    }
}

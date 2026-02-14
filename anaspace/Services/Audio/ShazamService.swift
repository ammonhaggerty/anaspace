@preconcurrency import AVFoundation
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

    private var session: SHSession?
    private let delegate = ShazamSessionDelegate()

    weak var audioService: AudioService?

    // MARK: - ObservationService Conformance

    func activate() async throws {
        result = nil
        isMatching = true

        let shazamSession = SHSession()
        shazamSession.delegate = delegate
        self.session = shazamSession

        delegate.onMatch = { [weak self] match in
            Task { @MainActor in
                guard let self else { return }
                guard let item = match.mediaItems.first else { return }

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
                self.isMatching = false
                print("[Shazam] Match: \(item.title ?? "?") by \(item.artist ?? "?")")
            }
        }

        delegate.onNoMatch = {
            print("[Shazam] No match for current segment, continuing...")
        }

        delegate.onError = { error in
            print("[Shazam] Error: \(error)")
        }

        // Register as AudioService consumer — buffers fed via shared AVAudioEngine
        nonisolated(unsafe) let unsafeSession = shazamSession
        audioService?.registerConsumer(id: "shazam") { buffer, time in
            unsafeSession.matchStreamingBuffer(buffer, at: time)
        }
    }

    func deactivate() {
        audioService?.removeConsumer(id: "shazam")
        delegate.onMatch = nil
        delegate.onNoMatch = nil
        delegate.onError = nil
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

// MARK: - Shazam Session Delegate

private final class ShazamSessionDelegate: NSObject, SHSessionDelegate {

    var onMatch: ((SHMatch) -> Void)?
    var onNoMatch: (() -> Void)?
    var onError: ((Error) -> Void)?

    func session(_ session: SHSession, didFind match: SHMatch) {
        onMatch?(match)
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        if let error {
            onError?(error)
        } else {
            onNoMatch?()
        }
    }
}

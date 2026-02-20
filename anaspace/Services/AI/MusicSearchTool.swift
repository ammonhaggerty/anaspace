import Foundation
import FoundationModels
import MusicKit

// MARK: - MusicSearch Tool

struct MusicSearchTool: Tool {
    let name = "searchMusic"
    let description = "Search Apple Music for artists, albums, and songs"

    @Generable
    struct Arguments {
        @Guide(description: "Artist or album name to search")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard MusicAuthorization.currentStatus == .authorized else {
            return "Music search unavailable."
        }

        var request = MusicCatalogSearchRequest(term: arguments.query, types: [Artist.self, Album.self])
        request.limit = 5

        let response = try await request.response()

        var parts: [String] = []

        for artist in response.artists.prefix(3) {
            let genres = (artist.genreNames ?? []).prefix(2).joined(separator: ", ")
            var line = "\(artist.name)"
            if !genres.isEmpty { line += " (\(genres))" }
            parts.append(line)
        }

        for album in response.albums.prefix(3) {
            let year = album.releaseDate.map { "\(Calendar.current.component(.year, from: $0))" } ?? "?"
            parts.append("\(album.artistName) - \(album.title) (\(year))")
        }

        let result = parts.joined(separator: "; ")
        return String(result.prefix(300))
    }
}

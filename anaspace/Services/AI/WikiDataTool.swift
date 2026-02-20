import FoundationModels
import Foundation

// MARK: - WikiData Tool

struct WikiDataTool: Tool {
    let name = "searchWikiData"
    let description = "Search for cultural events, venues, movements, and people by place and time period"

    @Generable
    struct Arguments {
        @Guide(description: "Search query combining topic and place, e.g. 'punk venues London' or 'jazz festival Detroit'")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let results = try await searchWikiData(query: arguments.query)
        guard !results.isEmpty else {
            return "No results found."
        }

        let text = results.prefix(5).joined(separator: "; ")
        return String(text.prefix(400))
    }

    // MARK: - WikiData API

    private func searchWikiData(query: String) async throws -> [String] {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "wbsearchentities"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let searchResponse = try JSONDecoder().decode(WikiSearchResponse.self, from: data)

        return searchResponse.search.map { entity in
            var line = entity.label
            if let desc = entity.description {
                line += " — \(String(desc.prefix(100)))"
            }
            return line
        }
    }
}

// MARK: - WikiData Response Types

private struct WikiSearchResponse: Decodable, Sendable {
    let search: [WikiEntity]
}

private struct WikiEntity: Decodable, Sendable {
    let id: String
    let label: String
    let description: String?
}

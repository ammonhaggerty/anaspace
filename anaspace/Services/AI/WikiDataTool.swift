import FoundationModels
import Foundation

// MARK: - Wikipedia & WikiData Search

/// Shared search utilities for grounding the on-device model with real facts.
enum WikiDataSearch {

    /// Basic WikiData entity search (used by WikiDataTool).
    static func search(query: String) async throws -> [String] {
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

    /// Fetch Wikipedia article content about the local music/culture scene,
    /// extracting paragraphs that mention the target year or decade.
    /// Uses the wikitext parse API for full article content (extract API truncates).
    static func fetchArticleExtract(city: String, year: Int, maxChars: Int = 800) async -> String? {
        // Step 1: Search Wikipedia for a relevant article
        guard let title = await searchWikipediaTitle(query: "music \(city)") else { return nil }

        // Step 2: Fetch the full article wikitext
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: title),
            URLQueryItem(name: "prop", value: "wikitext"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(WikiParseResponse.self, from: data)
            guard let wikitext = response.parse?.wikitext?.text, !wikitext.isEmpty else { return nil }

            // Step 3: Strip wiki markup to plaintext
            let plaintext = stripWikiMarkup(wikitext)

            // Step 4: Extract year-relevant paragraphs
            return extractRelevantText(from: plaintext, year: year, maxChars: maxChars)
        } catch {
            print("[WikiData] Parse fetch error: \(error)")
            return nil
        }
    }

    /// Strip wiki markup to rough plaintext.
    private static func stripWikiMarkup(_ text: String) -> String {
        var result = text
        // [[link|display]] → display, [[link]] → link
        result = result.replacing(#/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/#) { $0.output.1 }
        // Remove templates {{...}}
        result = result.replacing(#/\{\{[^}]*\}\}/#, with: "")
        // Remove refs <ref>...</ref> and <ref ... />
        result = result.replacing(#/<ref[^>]*>.*?<\/ref>/#, with: "")
        result = result.replacing(#/<ref[^\/]*\/>/#, with: "")
        // Remove remaining HTML tags
        result = result.replacing(#/<[^>]+>/#, with: "")
        // Remove bold/italic markers
        result = result.replacing(#/'{2,}/#, with: "")
        // Remove section headers (== Title ==) but keep as paragraph breaks
        result = result.replacing(#/=+\s*[^=\n]+\s*=+/#, with: "\n")
        // Remove wiki tables, categories, files
        result = result.replacing(#/\[\[Category:[^\]]*\]\]/#, with: "")
        result = result.replacing(#/\[\[File:[^\]]*\]\]/#, with: "")
        return result
    }

    /// Pull paragraphs mentioning the target year/decade, with intro as fallback.
    private static func extractRelevantText(from text: String, year: Int, maxChars: Int) -> String {
        let decade = (year / 10) * 10
        let yearStr = String(year)
        let decadeStr = "\(decade)s"
        let decadeAlt = "\(decade)"

        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 40 } // Skip short lines (headers, stubs)

        // Score each paragraph by year relevance
        let scored = paragraphs.enumerated().map { (index, para) -> (String, Int) in
            var score = 0
            if para.contains(yearStr) { score += 3 }
            if para.contains(decadeStr) || para.contains(decadeAlt) { score += 2 }
            let prevDecade = "\(decade - 10)"
            let nextDecade = "\(decade + 10)"
            if para.contains(prevDecade) || para.contains(nextDecade) { score += 1 }
            if index == 0 { score += 1 }
            return (para, score)
        }

        // Take highest-scoring paragraphs, up to maxChars
        let ranked = scored.sorted { $0.1 > $1.1 }
        var result = ""
        for (para, score) in ranked where score > 0 {
            if result.count + para.count + 1 > maxChars { break }
            if !result.isEmpty { result += " " }
            result += para
        }

        // Fallback: first paragraph if nothing scored
        if result.isEmpty {
            result = String(text.prefix(maxChars))
        }

        return result
    }

    /// Search Wikipedia for the best matching article title.
    private static func searchWikipediaTitle(query: String) async -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "1"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(WikipediaSearchResponse.self, from: data)
            return response.query.search.first?.title
        } catch {
            print("[WikiData] Search error: \(error)")
            return nil
        }
    }
}

// MARK: - Wikipedia Response Types

private struct WikipediaSearchResponse: Decodable, Sendable {
    let query: WikipediaSearchQuery
}

private struct WikipediaSearchQuery: Decodable, Sendable {
    let search: [WikipediaSearchResult]
}

private struct WikipediaSearchResult: Decodable, Sendable {
    let title: String
}

private struct WikipediaQueryResponse: Decodable, Sendable {
    let query: WikipediaPages
}

private struct WikipediaPages: Decodable, Sendable {
    let pages: [String: WikipediaPage]
}

private struct WikipediaPage: Decodable, Sendable {
    let extract: String?
}

private struct WikiParseResponse: Decodable, Sendable {
    let parse: WikiParseContent?
}

private struct WikiParseContent: Decodable, Sendable {
    let wikitext: WikiParseText?
}

private struct WikiParseText: Decodable, Sendable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case text = "*"
    }
}

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
        let results = try await WikiDataSearch.search(query: arguments.query)
        guard !results.isEmpty else {
            return "No results found."
        }

        let text = results.prefix(5).joined(separator: "; ")
        return String(text.prefix(400))
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

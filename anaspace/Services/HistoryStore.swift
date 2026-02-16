import Foundation

// MARK: - History Entry

struct HistoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let result: ClaudeResult
    let locationLabel: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var displayLine: String {
        let raw = "\(result.subject) | \(result.year) | \(locationLabel)"
            .uppercased()
        if raw.count <= 31 {
            return raw
        }
        return String(raw.prefix(29)) + ".."
    }
}

// MARK: - History Store

@Observable @MainActor
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private static let maxEntries = 12
    private static let fileName = "history.json"

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func promote(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              index != 0 else { return }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        save()
    }

    func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func save() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(entries)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Self.fileName)
    }
}

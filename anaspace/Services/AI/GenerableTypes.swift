import FoundationModels

// MARK: - Tier 1: Culture Map

@Generable(description: "A culture map anchored to a subject, place, and year")
struct CultureMap {
    @Guide(description: "Primary subject name, ALL CAPS, max 20 characters")
    var subject: String

    @Guide(description: "One of: artist, band, album, venue, event, movement, producer, label")
    var subjectType: String

    @Guide(description: "Birth or founding info, e.g. B. 1942, LONDON")
    var birthInfo: String

    @Guide(description: "City, State | Country")
    var place: String

    @Guide(description: "Anchoring year")
    var year: Int

    @Guide(description: "8 culturally connected entities", .count(8))
    var entities: [CultureEntity]

    @Guide(description: "5 artist names for playlist. Empty array if subject is an artist.", .count(0...5))
    var keyArtists: [String]

    @Guide(description: "One sentence connecting subject to place and year")
    var narrative: String
}

@Generable(description: "A culturally connected entity")
struct CultureEntity {
    @Guide(description: "Entity name, ALL CAPS, max 20 characters")
    var name: String

    @Guide(description: "Optional distinguishing detail, or empty string")
    var subtitle: String

    @Guide(description: "One of: collaborator, peer, influence, follower, creation, place, event, movement")
    var entityType: String

    @Guide(description: "One sentence: how this entity connects to the subject in this place and year")
    var relationship: String

    @Guide(description: "Relevance score, 0.9+ reserved for direct collaborators", .range(0.0...1.0))
    var relevance: Double
}

// MARK: - Tier 3: Entity Detail

@Generable(description: "Detailed information about a culture map entity")
struct EntityDetail {
    @Guide(description: "2 paragraph bio grounded in the specific year and place, 300-400 characters")
    var bio: String

    @Guide(description: "200-300 characters explaining specific connection to the subject")
    var description: String

    @Guide(description: "A song title by or associated with this entity, or empty string if none")
    var recommendedSong: String
}

// MARK: - CultureMap → ClaudeResult Conversion

extension CultureMap {
    /// Convert a fully generated CultureMap to a ClaudeResult for downstream compatibility.
    func toClaudeResult(isStreaming: Bool = false) -> ClaudeResult {
        let connections = entities.map { entity in
            CultureConnection(
                name: entity.name,
                subtitle: entity.subtitle.isEmpty ? nil : entity.subtitle,
                entityType: EntityType(rawValue: entity.entityType) ?? .peer,
                relationship: entity.relationship,
                relevance: entity.relevance,
                description: "",
                recommendedSong: nil
            )
        }

        return ClaudeResult(
            subject: subject,
            subjectType: subjectType,
            birthInfo: birthInfo,
            place: place,
            year: year,
            bio: "",
            narrative: narrative,
            connections: connections,
            keyArtists: keyArtists,
            isStreaming: isStreaming
        )
    }
}

extension CultureMap.PartiallyGenerated {
    /// Convert a partially generated CultureMap to a streaming ClaudeResult.
    func toClaudeResult() -> ClaudeResult {
        let connections = (entities ?? []).compactMap { partial -> CultureConnection? in
            guard let name = partial.name, !name.isEmpty else { return nil }
            return CultureConnection(
                name: name,
                subtitle: (partial.subtitle ?? "").isEmpty ? nil : partial.subtitle,
                entityType: EntityType(rawValue: partial.entityType ?? "peer") ?? .peer,
                relationship: partial.relationship ?? "",
                relevance: partial.relevance ?? 0.5,
                description: "",
                recommendedSong: nil
            )
        }

        return ClaudeResult(
            subject: subject ?? "...",
            subjectType: subjectType ?? "artist",
            birthInfo: birthInfo ?? "",
            place: place ?? "",
            year: year ?? 0,
            bio: "",
            narrative: narrative ?? "",
            connections: connections,
            keyArtists: keyArtists ?? [],
            isStreaming: true
        )
    }
}

import CoreLocation
import Foundation

// MARK: - Observation Service Protocol

@MainActor
protocol ObservationService {
    var isAvailable: Bool { get }
    func activate() async throws
    func deactivate()
}

// MARK: - Observation Phase

enum ObservationPhase: String, Sendable {
    case idle
    case capturing   // Audio active, services listening
    case processing  // Audio stopped; Claude/late Shazam still running
    case resolved    // All done
}

// MARK: - Observation Mode

enum ObservationMode: String, Codable, Sendable {
    case tap
    case hold
}

// MARK: - Audio Scene

enum AudioScene: String, Codable, Sendable {
    case music
    case speech
    case musicAndSpeech
    case singing
    case silence
    case ambient
    case unknown
}

// MARK: - Shazam Result

struct ShazamResult: Sendable {
    let title: String
    let artist: String
    let album: String?
    let appleMusicID: String?
    let genres: [String]
    let releaseYear: Int?
    let artworkURL: URL?
    let confidence: Double
}

// MARK: - Transcript Result

struct TranscriptResult: Sendable {
    let text: String
    let confidence: Double
    let isFinal: Bool

    var wordCount: Int {
        text.split(separator: " ").count
    }
}

// MARK: - Location Result

struct LocationResult: @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D
    let placeName: String?
    let neighborhood: String?
    let city: String?
    let state: String?
    let country: String?
    let isoCountryCode: String?
}

// MARK: - Resolution Trigger

enum ResolutionTrigger: String, Codable, Sendable {
    case shazamMatch
    case silenceTimeout
    case hardTimeout
    case userRelease
}

// MARK: - Observation Signals

struct ObservationSignals: Sendable {
    var shazamResult: ShazamResult?
    var transcript: TranscriptResult?
    var audioScene: AudioScene
    var location: LocationResult?
    var timestamp: Date
    var mode: ObservationMode
    var duration: TimeInterval
    var resolutionTrigger: ResolutionTrigger

    // Active triad context — set when user has an existing observation loaded
    var activeSubject: String?
    var activeYear: Int?
    var activeLocationLabel: String?

    var hasActiveTriad: Bool {
        activeSubject != nil && activeYear != nil && activeLocationLabel != nil
    }

    init(
        shazamResult: ShazamResult? = nil,
        transcript: TranscriptResult? = nil,
        audioScene: AudioScene = .unknown,
        location: LocationResult? = nil,
        timestamp: Date = .now,
        mode: ObservationMode = .tap,
        duration: TimeInterval = 0,
        resolutionTrigger: ResolutionTrigger = .hardTimeout,
        activeSubject: String? = nil,
        activeYear: Int? = nil,
        activeLocationLabel: String? = nil
    ) {
        self.shazamResult = shazamResult
        self.transcript = transcript
        self.audioScene = audioScene
        self.location = location
        self.timestamp = timestamp
        self.mode = mode
        self.duration = duration
        self.resolutionTrigger = resolutionTrigger
        self.activeSubject = activeSubject
        self.activeYear = activeYear
        self.activeLocationLabel = activeLocationLabel
    }
}

// MARK: - Entity Type

enum EntityType: String, Codable, Sendable {
    case collaborator
    case peer
    case influence
    case follower
    case creation    // songs, albums, works
    case place       // venues, studios, landmarks
    case event       // historical/cultural events
    case movement    // genres, cultural movements

    var glyph: Character {
        switch self {
        case .collaborator: return "\u{25A0}"  // ■ black square
        case .peer:         return "\u{25AA}"  // ▪ black small square
        case .influence:    return "\u{21A2}"  // ↢ leftwards arrow with tail
        case .follower:     return "\u{21A3}"  // ↣ rightwards arrow with tail
        case .creation:     return "\u{2B58}"  // ⭘ heavy circle
        case .place:        return "\u{2207}"  // ∇ nabla
        case .event:        return "\u{26A1}"  // ⚡ high voltage
        case .movement:     return "\u{224B}"  // ≋ triple tilde
        }
    }

    /// Whether this entity type represents a person/artist with a searchable music catalog.
    var hasArtistCatalog: Bool {
        switch self {
        case .collaborator, .peer, .influence, .follower: return true
        case .creation, .place, .event, .movement: return false
        }
    }

    /// Default relationship description for this entity type.
    func defaultRelationship(for subject: String) -> String {
        switch self {
        case .collaborator: return "Close collaborator of \(subject)"
        case .peer:         return "Musical peer of \(subject)"
        case .influence:    return "Key influence on \(subject)"
        case .follower:     return "Influenced by \(subject)"
        case .creation:     return "Notable work by \(subject)"
        case .place:        return "Venue associated with \(subject)"
        case .event:        return "Event connected to \(subject)"
        case .movement:     return "Movement encompassing \(subject)"
        }
    }
}

// MARK: - Culture Connection

struct CultureConnection: Codable, Sendable {
    let name: String
    let subtitle: String?
    let entityType: EntityType
    let relationship: String
    let relevance: Double
    let description: String
    let recommendedSong: String?
}

// MARK: - Claude Result

struct ClaudeResult: Codable, Sendable {
    let subject: String
    let subjectType: String
    let birthInfo: String
    let place: String
    let year: Int
    let bio: String
    let narrative: String
    let connections: [CultureConnection]
    let keyArtists: [String]
    let isPartial: Bool

    init(subject: String, subjectType: String, birthInfo: String, place: String, year: Int, bio: String, narrative: String, connections: [CultureConnection], keyArtists: [String] = [], isPartial: Bool) {
        self.subject = subject
        self.subjectType = subjectType
        self.birthInfo = birthInfo
        self.place = place
        self.year = year
        self.bio = bio
        self.narrative = narrative
        self.connections = connections
        self.keyArtists = keyArtists
        self.isPartial = isPartial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decode(String.self, forKey: .subject)
        subjectType = try c.decode(String.self, forKey: .subjectType)
        birthInfo = try c.decode(String.self, forKey: .birthInfo)
        place = try c.decode(String.self, forKey: .place)
        year = try c.decode(Int.self, forKey: .year)
        bio = try c.decode(String.self, forKey: .bio)
        narrative = try c.decode(String.self, forKey: .narrative)
        connections = try c.decode([CultureConnection].self, forKey: .connections)
        keyArtists = try c.decodeIfPresent([String].self, forKey: .keyArtists) ?? []
        isPartial = try c.decodeIfPresent(Bool.self, forKey: .isPartial) ?? false
    }
}

// MARK: - Service Configuration

struct ServiceConfiguration: Sendable {
    let holdThresholdMs: Int
    let hardTimeoutSeconds: TimeInterval
    let silenceTimeoutSeconds: TimeInterval
    let shazamConfidenceThreshold: Double
    let speechConfidenceThreshold: Double
    let commandMaxWords: Int
    let discardShortTranscripts: Int
    let locationCascadeMaxLevel: Int
    let voiceOverridesShazam: Bool
    let lyricIdEnabled: Bool
    let shazamTimeoutSeconds: TimeInterval

    init(
        holdThresholdMs: Int = 300,
        hardTimeoutSeconds: TimeInterval = 10,
        silenceTimeoutSeconds: TimeInterval = 5,
        shazamConfidenceThreshold: Double = 0.7,
        speechConfidenceThreshold: Double = 0.4,
        commandMaxWords: Int = 20,
        discardShortTranscripts: Int = 3,
        locationCascadeMaxLevel: Int = 4,
        voiceOverridesShazam: Bool = true,
        lyricIdEnabled: Bool = true,
        shazamTimeoutSeconds: TimeInterval = 12
    ) {
        self.holdThresholdMs = holdThresholdMs
        self.hardTimeoutSeconds = hardTimeoutSeconds
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
        self.shazamConfidenceThreshold = shazamConfidenceThreshold
        self.speechConfidenceThreshold = speechConfidenceThreshold
        self.commandMaxWords = commandMaxWords
        self.discardShortTranscripts = discardShortTranscripts
        self.locationCascadeMaxLevel = locationCascadeMaxLevel
        self.voiceOverridesShazam = voiceOverridesShazam
        self.lyricIdEnabled = lyricIdEnabled
        self.shazamTimeoutSeconds = shazamTimeoutSeconds
    }
}

// MARK: - Player State

enum PlayerState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case fading
}

// MARK: - Track Info

struct TrackInfo: Sendable {
    let artist: String
    let title: String
    let year: Int
    let previewURL: URL
}

// MARK: - Service Error

enum ServiceError: Error {
    case audioFormatUnavailable
    case speechRecognizerUnavailable
}

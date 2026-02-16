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

    init(
        shazamResult: ShazamResult? = nil,
        transcript: TranscriptResult? = nil,
        audioScene: AudioScene = .unknown,
        location: LocationResult? = nil,
        timestamp: Date = .now,
        mode: ObservationMode = .tap,
        duration: TimeInterval = 0,
        resolutionTrigger: ResolutionTrigger = .hardTimeout
    ) {
        self.shazamResult = shazamResult
        self.transcript = transcript
        self.audioScene = audioScene
        self.location = location
        self.timestamp = timestamp
        self.mode = mode
        self.duration = duration
        self.resolutionTrigger = resolutionTrigger
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
}

// MARK: - Culture Connection

struct CultureConnection: Sendable {
    let name: String
    let subtitle: String?
    let entityType: EntityType
    let relationship: String
    let relevance: Double
}

// MARK: - Claude Result

struct ClaudeResult: Sendable {
    let subject: String
    let subjectType: String
    let birthInfo: String
    let place: String
    let year: Int
    let bio: String
    let narrative: String
    let connections: [CultureConnection]
    let isStreaming: Bool
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
        shazamTimeoutSeconds: TimeInterval = 10
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

// MARK: - Service Error

enum ServiceError: Error {
    case audioFormatUnavailable
    case speechRecognizerUnavailable
}

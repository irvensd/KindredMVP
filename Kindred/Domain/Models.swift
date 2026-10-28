import Foundation

enum Gender: String, CaseIterable, Identifiable, Codable, Sendable {
    case male = "Male", female = "Female"
    var id: String { rawValue }
}
enum Intention: String, CaseIterable, Identifiable, Codable, Sendable {
    case lifePartner = "A life partner", relationship = "A meaningful relationship", intentional = "Dating with intention"
    var id: String { rawValue }
}
enum SabbathPractice: String, CaseIterable, Identifiable, Codable, Sendable {
    case shareLater = "Prefer to share later", community = "Worship & community", restful = "A quiet, restful Sabbath", outdoors = "Faith & time outdoors", personal = "Still finding my rhythm"
    var id: String { rawValue }
}
enum FoodPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case vegetarian = "Vegetarian", plantBased = "Plant-based", flexible = "Flexible", privateChoice = "Prefer to share later"
    var id: String { rawValue }
}
enum Interest: String, CaseIterable, Identifiable, Codable, Sendable {
    case hiking = "Hiking", cooking = "Cooking", music = "Live music", books = "Good books", service = "Volunteering", travel = "Travel", art = "Art & design", fitness = "Movement", gardening = "Gardening", photography = "Photography", games = "Board games", nature = "Slow Sundays"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .hiking: "mountain.2"; case .cooking: "fork.knife"; case .music: "music.note"; case .books: "book"
        case .service: "hands.sparkles"; case .travel: "airplane"; case .art: "paintpalette"; case .fitness: "figure.walk"
        case .gardening: "leaf"; case .photography: "camera"; case .games: "dice"; case .nature: "sun.max"
        }
    }
}
struct ProfilePhoto: Identifiable, Equatable, Sendable {
    var id: String
    var assetName: String?
    var localData: Data?
    var caption: String
    static func bundled(_ name: String, caption: String) -> Self { .init(id: name, assetName: name, caption: caption) }
}
struct ProfilePrompt: Identifiable, Equatable, Sendable {
    var id: String
    var question: String
    var answer: String
}
struct FaithPreferences: Equatable, Sendable {
    var sabbath: SabbathPractice = .shareLater
    var food: FoodPreference = .privateChoice
    var meaning: String = ""
}
struct MemberProfile: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var age: Int
    var gender: Gender
    var city: String
    var distanceMiles: Int
    var occupation: String
    var bio: String
    var intention: Intention
    var faith: FaithPreferences
    var interests: Set<Interest>
    var prompts: [ProfilePrompt]
    var photos: [ProfilePhoto]
    var isDemo: Bool = true
}
struct DatingPreferences: Equatable, Sendable {
    var genders: Set<Gender> = Set(Gender.allCases)
    var minimumAge = 24
    var maximumAge = 38
}
struct DiscoveryPreferences: Equatable, Sendable {
    var dating = DatingPreferences()
    var radiusMiles = 75
}
struct PrivacyPreferences: Equatable, Sendable {
    var showCity = true
    var discoveryPaused = false
}
struct NotificationPreferences: Equatable, Sendable {
    var likes = true
    var messages = true
    var sabbathQuietMode = false
}
struct Like: Identifiable, Equatable, Sendable {
    let id: String
    let senderID: String
    let recipientID: String
    let promptID: String?
    var photoID: String? = nil
    let createdAt: Date
}
struct Match: Identifiable, Equatable, Sendable {
    let id: String
    let memberID: String
    let createdAt: Date
}
struct Message: Identifiable, Equatable, Sendable {
    let id: String
    let senderID: String
    let text: String
    let createdAt: Date
}
struct Conversation: Identifiable, Equatable, Sendable {
    let id: String
    let memberID: String
    var messages: [Message]
    var unreadCount: Int
}
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case inappropriate = "Inappropriate content", impersonation = "Impersonation", harassment = "Harassment", underage = "May be under 18", other = "Something else"
    var id: String { rawValue }
}
struct Report: Identifiable, Equatable, Sendable {
    let id: String
    let memberID: String
    let reason: ReportReason
    let details: String
    let createdAt: Date
}
struct Block: Identifiable, Equatable, Sendable {
    var id: String { memberID }
    let memberID: String
    let createdAt: Date
}
struct SessionSnapshot: Sendable {
    var currentProfile: MemberProfile
    var members: [MemberProfile]
    var likes: [Like]
    var matches: [Match]
    var conversations: [Conversation]
    var passedIDs: Set<String> = []
    var blocks: [Block] = []
    var reports: [Report] = []
    var discovery = DiscoveryPreferences()
    var privacy = PrivacyPreferences()
    var notifications = NotificationPreferences()
}
enum KindredError: LocalizedError, Equatable {
    case invalid(String), unavailable
    var errorDescription: String? {
        switch self {
        case .invalid(let text): text
        case .unavailable: "This demo profile or conversation is no longer available."
        }
    }
}
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

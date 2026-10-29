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
    var cropZoom: Double = 1
    var cropX: Double = 0
    var cropY: Double = 0
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

struct ProfileValidationIssue: Identifiable, Equatable {
    let id: String
    let message: String
}
extension MemberProfile {
    /// Ordered to match the profile editor; shared with the repository save boundary.
    var validationIssues: [ProfileValidationIssue] {
        var issues: [ProfileValidationIssue] = []
        if !(1...40).contains(name.trimmed.count) {
            issues.append(.init(id: "name", message: name.trimmed.isEmpty ? "Enter your first name." : "Keep your first name to 40 characters or fewer."))
        }
        if !(2...60).contains(city.trimmed.count) {
            issues.append(.init(id: "city", message: "Enter a city or general area using 2–60 characters."))
        }
        if bio.count > 500 { issues.append(.init(id: "bio", message: "Shorten your bio to 500 characters or fewer (currently \(bio.count)).")) }
        if interests.count > 8 { issues.append(.init(id: "interests", message: "Choose up to 8 interests.")) }
        if faith.meaning.count > 300 { issues.append(.init(id: "faith", message: "Shorten your faith note to 300 characters or fewer (currently \(faith.meaning.count)).")) }
        if prompts.count != 3 { issues.append(.init(id: "prompts", message: "Your profile needs three prompt slots. Answers can stay blank.")) }
        for prompt in prompts where !prompt.answer.trimmed.isEmpty && !(5...240).contains(prompt.answer.trimmed.count) {
            issues.append(.init(id: "prompt-" + prompt.id, message: "Use 5–240 characters for this answer, or leave it blank."))
        }
        if !(1...6).contains(photos.count) { issues.append(.init(id: "photos", message: photos.isEmpty ? "Add at least one profile photo." : "Keep up to 6 profile photos.")) }
        if age < 18 { issues.append(.init(id: "age", message: "Your profile must have an age of 18 or older.")) }
        return issues
    }
}

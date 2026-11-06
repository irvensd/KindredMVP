import Foundation

struct MessageDay: Identifiable {
    let date: Date
    var messages: [Message]
    var id: Date { date }
}
extension Conversation {
    /// Group by the user's calendar day, including DST boundaries.
    func days(calendar: Calendar = .current) -> [MessageDay] {
        var result: [MessageDay] = []
        for message in messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            let day = calendar.startOfDay(for: message.createdAt)
            if result.last?.date == day { result[result.count - 1].messages.append(message) }
            else { result.append(MessageDay(date: day, messages: [message])) }
        }
        return result
    }
    var preview: String {
        guard let message = messages.last else { return "A new connection. Start with a little hello." }
        return (message.senderID == "me" ? "You: " : "") + message.text
    }
}
struct ConversationStarter: Identifiable {
    let id: String
    let question: String
    let answer: String
    let draft: String
}
extension MemberProfile {
    var conversationStarters: [ConversationStarter] {
        prompts.filter { !$0.answer.trimmed.isEmpty }.prefix(2).map {
            ConversationStarter(id: $0.id, question: $0.question, answer: $0.answer,
                                draft: "Hi \(name)! Your answer to “\($0.question)” caught my eye. I'd love to hear more.")
        }
    }
    /// An optional story checklist, not a score for faith or compatibility.
    var storySections: [(title: String, complete: Bool)] {
        [("A little about you", !bio.trimmed.isEmpty),
         ("Your interests", !interests.isEmpty),
         ("Your voice", prompts.contains { !$0.answer.trimmed.isEmpty })]
    }
    var completedStorySections: Int { storySections.filter(\.complete).count }
    var missingStorySections: [String] { storySections.filter { !$0.complete }.map(\.title) }
}

/// Resolved against the recipient, since bundled photos can be shared by members.
enum SavedInterestTarget: Hashable {
    case photo(String)
    case answer(String)
}

struct SavedInterest: Identifiable {
    let target: SavedInterestTarget
    let id: String
    let title: String
    var answer: String? = nil
    var photo: ProfilePhoto? = nil
}
extension Like {
    func detail(in member: MemberProfile) -> SavedInterest? {
        guard recipientID == member.id else { return nil }
        if let photoID, let index = member.photos.firstIndex(where: { $0.id == photoID }) {
            return SavedInterest(target: .photo(photoID), id: id, title: "\(member.name)’s photo \(index + 1)", photo: member.photos[index])
        }
        if let promptID, let prompt = member.prompts.first(where: { $0.id == promptID }), !prompt.answer.trimmed.isEmpty {
            return SavedInterest(target: .answer(promptID), id: id, title: "\(member.name)’s answer to “\(prompt.question)”", answer: prompt.answer)
        }
        return nil
    }
}


// Offline city-center estimates for the prototype's supported search areas.
enum SearchCity: String, CaseIterable, Identifiable, Sendable {
    case chicago = "Chicago, IL", evanston = "Evanston, IL", oakPark = "Oak Park, IL"
    case madison = "Madison, WI", atlanta = "Atlanta, GA", dallas = "Dallas, TX"
    case newYork = "New York, NY", lomaLinda = "Loma Linda, CA"
    var id: String { rawValue }
    var coordinates: (latitude: Double, longitude: Double) {
        switch self {
        case .chicago: (41.88, -87.63)
        case .evanston: (42.04, -87.69)
        case .oakPark: (41.89, -87.78)
        case .madison: (43.07, -89.40)
        case .atlanta: (33.75, -84.39)
        case .dallas: (32.78, -96.80)
        case .newYork: (40.71, -74.01)
        case .lomaLinda: (34.05, -117.26)
        }
    }
    static func matching(_ city: String) -> Self? {
        allCases.first { $0.rawValue.compare(city.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
    func miles(to city: Self) -> Int {
        let origin = coordinates
        let destination = city.coordinates
        let radians = Double.pi / 180
        let lat = (destination.latitude - origin.latitude) * radians
        let lon = (destination.longitude - origin.longitude) * radians
        let a = pow(sin(lat / 2), 2) + cos(origin.latitude * radians) * cos(destination.latitude * radians) * pow(sin(lon / 2), 2)
        return Int((3958.8 * 2 * asin(sqrt(min(1, max(0, a))))).rounded())
    }
}
enum LocationStatus: String, CaseIterable, Identifiable, Sendable {
    case home = "None", visiting = "Visiting", moving = "Moving to"
    var id: String { rawValue }
}
extension MemberProfile {
    var travelDescription: String? {
        locationStatus == .home ? nil : "\(locationStatus.rawValue) \(destination.rawValue) · self-reported"
    }
}

enum DistanceOpenness: String, CaseIterable, Identifiable, Sendable {
    case unspecified = "Not shared"
    case local = "Prefer local connections"
    case longDistance = "Open to long distance"
    var id: String { rawValue }
}

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
struct SavedInterest: Identifiable {
    let id: String
    let title: String
    var answer: String? = nil
    var photo: ProfilePhoto? = nil
}
extension Like {
    func detail(in member: MemberProfile) -> SavedInterest? {
        guard recipientID == member.id else { return nil }
        if let photoID, let index = member.photos.firstIndex(where: { $0.id == photoID }) {
            return SavedInterest(id: id, title: "\(member.name)’s photo \(index + 1)", photo: member.photos[index])
        }
        if let promptID, let prompt = member.prompts.first(where: { $0.id == promptID }) {
            return SavedInterest(id: id, title: "\(member.name)’s answer to “\(prompt.question)”", answer: prompt.answer)
        }
        return nil
    }
}

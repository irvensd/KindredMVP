import Foundation

@MainActor
protocol KindredRepository: AnyObject {
    func snapshot() -> SessionSnapshot
    func like(memberID: String, promptID: String?, photoID: String?) throws
    func removeLike(memberID: String)
    func unmatch(memberID: String) throws
    func pass(memberID: String) throws
    func undoPass(memberID: String) throws
    func resetPasses()
    func block(memberID: String) throws
    func unblock(memberID: String)
    func report(memberID: String, reason: ReportReason, details: String) throws
    func send(text: String, conversationID: String) throws
    func markRead(conversationID: String)
    func updateProfile(_ profile: MemberProfile) throws
    func updateDiscovery(_ preferences: DiscoveryPreferences) throws
    func updatePrivacy(_ preferences: PrivacyPreferences)
    func updateNotifications(_ preferences: NotificationPreferences)
}

@MainActor
final class InMemoryKindredRepository: KindredRepository {
    private var state: SessionSnapshot
    private var conversationsWithLoadedHistory: Set<String> = []
    private let now: () -> Date
    init(state: SessionSnapshot? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.state = state ?? DemoData.snapshot(now: now())
    }
    func snapshot() -> SessionSnapshot { state }
    func replaceMembers(_ members: [MemberProfile]) { state.members = members }
    func replaceBlocks(_ summaries: [BackendAccount.BlockedMemberSummary]) {
        state.blocks = summaries.map {
            Block(memberID: $0.blocked_id.uuidString.lowercased(), createdAt: now(), displayName: $0.display_name)
        }
    }
    func replaceActivity(_ activity: BackendAccount.Activity) {
        state.likes = activity.likes
        state.matches = activity.matches
        let previous = Dictionary(uniqueKeysWithValues: state.conversations.map { ($0.id, $0) })
        state.conversations = activity.conversations.map { latest in
            guard conversationsWithLoadedHistory.contains(latest.id),
                  let history = previous[latest.id],
                  let combined = mergeHistory(history, into: latest) else {
                conversationsWithLoadedHistory.remove(latest.id)
                return latest
            }
            return combined
        }
        conversationsWithLoadedHistory.formIntersection(state.conversations.map(\.id))
        state.unmatchedIDs = activity.endedMemberIDs
    }

    func prependHistory(_ page: BackendAccount.MessagePage, to previous: Conversation) {
        guard let index = state.conversations.firstIndex(where: { $0.id == previous.id }) else { return }
        var history = previous
        history.messages.insert(contentsOf: page.messages, at: 0)
        history.hasOlderMessages = page.hasMore
        guard let combined = mergeHistory(history, into: state.conversations[index]) else { return }
        state.conversations[index] = combined
        conversationsWithLoadedHistory.insert(previous.id)
    }

    private func mergeHistory(_ history: Conversation, into latest: Conversation) -> Conversation? {
        // Only merge contiguous windows. A refresh can have replaced the latest
        // batch while a page request was in flight.
        guard let first = latest.messages.first,
              let overlap = history.messages.firstIndex(where: { $0.id == first.id }) else { return nil }
        var conversation = latest
        conversation.messages = Array(history.messages[..<overlap]) + latest.messages
        conversation.hasOlderMessages = history.hasOlderMessages
        return conversation
    }

    private func requireMember(_ id: String) throws {
        guard state.members.contains(where: { $0.id == id }), !state.blocks.contains(where: { $0.memberID == id }) else { throw KindredError.unavailable }
    }
    func like(memberID: String, promptID: String?, photoID: String?) throws {
        try requireMember(memberID)
        guard promptID == nil || photoID == nil else { throw KindredError.invalid("Choose one photo or answer at a time.") }
        let member = state.members.first { $0.id == memberID }!
        if let photoID, !member.photos.contains(where: { $0.id == photoID }) {
            throw KindredError.invalid("That photo is no longer available.")
        }
        if let promptID, !member.prompts.contains(where: { $0.id == promptID && !$0.answer.trimmed.isEmpty }) {
            throw KindredError.invalid("That prompt is no longer available.")
        }
        guard !state.likes.contains(where: { $0.senderID == "me" && $0.recipientID == memberID && $0.promptID == promptID && $0.photoID == photoID }) else { return }
        state.likes.append(.init(id: UUID().uuidString, senderID: "me", recipientID: memberID, promptID: promptID, photoID: photoID, createdAt: now()))
        if state.likes.contains(where: { $0.senderID == memberID && $0.recipientID == "me" }), !state.matches.contains(where: { $0.memberID == memberID }) {
            state.matches.append(.init(id: "match-\(memberID)", memberID: memberID, createdAt: now()))
            if !state.conversations.contains(where: { $0.memberID == memberID }) {
                state.conversations.append(.init(id: "chat-\(memberID)", memberID: memberID, messages: [], unreadCount: 0))
            }
        }
    }
    func removeLike(memberID: String) {
        state.likes.removeAll { $0.senderID == "me" && $0.recipientID == memberID }
        // Removing a like does not delete an existing match or conversation.
    }
    func unmatch(memberID: String) throws {
        try requireMember(memberID)
        guard state.matches.contains(where: { $0.memberID == memberID }) else { throw KindredError.unavailable }
        state.unmatchedIDs.insert(memberID)
        state.matches.removeAll { $0.memberID == memberID }
        state.conversations.removeAll { $0.memberID == memberID }
        state.likes.removeAll { $0.senderID == memberID || $0.recipientID == memberID }
    }
    func pass(memberID: String) throws { try requireMember(memberID); state.passedIDs.insert(memberID) }
    func undoPass(memberID: String) throws { try requireMember(memberID); state.passedIDs.remove(memberID) }
    func resetPasses() { state.passedIDs.removeAll() }
    func block(memberID: String) throws {
        try requireMember(memberID)
        state.blocks.append(.init(memberID: memberID, createdAt: now()))
        state.likes.removeAll { $0.senderID == memberID || $0.recipientID == memberID }
        state.matches.removeAll { $0.memberID == memberID }
        state.conversations.removeAll { $0.memberID == memberID }
    }
    func unblock(memberID: String) { state.blocks.removeAll { $0.memberID == memberID } }
    func report(memberID: String, reason: ReportReason, details: String) throws {
        try requireMember(memberID)
        guard details.count <= 1000 else { throw KindredError.invalid("Keep the report note to 1,000 characters.") }
        state.reports.append(.init(id: UUID().uuidString, memberID: memberID, reason: reason, details: details.trimmed, createdAt: now()))
    }
    func send(text: String, conversationID: String) throws {
        guard let index = state.conversations.firstIndex(where: { $0.id == conversationID }) else { throw KindredError.unavailable }
        try requireMember(state.conversations[index].memberID)
        guard (1...2000).contains(text.trimmed.count) else { throw KindredError.invalid("Write a message between 1 and 2,000 characters.") }
        state.conversations[index].messages.append(.init(id: UUID().uuidString, senderID: "me", text: text.trimmed, createdAt: now()))
    }
    func markRead(conversationID: String) {
        guard let index = state.conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        state.conversations[index].unreadCount = 0
    }
    func updateProfile(_ profile: MemberProfile) throws {
        guard profile.id == "me" else { throw KindredError.unavailable }
        let issues = profile.validationIssues
        guard issues.isEmpty else { throw KindredError.invalid(issues.map(\.message).joined(separator: "\n")) }
        var normalized = profile
        normalized.name = profile.name.trimmed
        normalized.city = profile.city.trimmed
        state.currentProfile = normalized
    }
    func updateDiscovery(_ preferences: DiscoveryPreferences) throws {
        guard preferences.isValid else { throw KindredError.invalid("Choose at least one dating preference and a valid adult age range and radius.") }
        state.discovery = preferences
    }
    func updatePrivacy(_ preferences: PrivacyPreferences) { state.privacy = preferences }
    func updateNotifications(_ preferences: NotificationPreferences) { state.notifications = preferences }
}

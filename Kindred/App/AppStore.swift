import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    private let repository: any KindredRepository
    private(set) var state: SessionSnapshot
    var onboarding = OnboardingDraft()
    var onboardingStep = 0
    var isOnboarding = false
    var hasCompletedOnboarding = false
    var errorMessage: String?
    private var conversationDrafts: [String: String] = [:]
    var feedback: String?
    var feedbackCount = 0
    var presentedMatch: Match?
    private let now: () -> Date

    init(repository: (any KindredRepository)? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        let source = repository ?? InMemoryKindredRepository(now: now)
        self.repository = source
        self.state = source.snapshot()
    }
    var blockedIDs: Set<String> { Set(state.blocks.map(\.memberID)) }
    func member(_ id: String) -> MemberProfile? {
        if id == "me" {
            var profile = state.currentProfile
            if !state.privacy.showCity { profile.city = "Location private" }
            return profile
        }
        return state.members.first { $0.id == id && !blockedIDs.contains(id) }
    }
    var discoveryProfiles: [MemberProfile] {
        guard !state.privacy.discoveryPaused else { return [] }
        return state.members.filter {
            !blockedIDs.contains($0.id) && !state.passedIDs.contains($0.id)
            && state.discovery.dating.genders.contains($0.gender)
            && (state.discovery.dating.minimumAge...state.discovery.dating.maximumAge).contains($0.age)
            && $0.distanceMiles <= state.discovery.radiusMiles
        }
    }
    var outgoingProfiles: [MemberProfile] { state.members.filter { !blockedIDs.contains($0.id) && isLiked($0.id) } }
    var incomingProfiles: [MemberProfile] {
        state.members.filter { person in !blockedIDs.contains(person.id) && state.likes.contains { $0.senderID == person.id && $0.recipientID == "me" } }
    }
    var conversations: [Conversation] {
        state.conversations.filter { !blockedIDs.contains($0.memberID) }.sorted {
            let left = lastActivity($0), right = lastActivity($1)
            return left == right ? $0.id < $1.id : left > right
        }
    }
    private func lastActivity(_ conversation: Conversation) -> Date {
        conversation.messages.last?.createdAt
            ?? state.matches.first { $0.memberID == conversation.memberID }?.createdAt ?? .distantPast
    }
    func isLiked(_ id: String) -> Bool { state.likes.contains { $0.senderID == "me" && $0.recipientID == id } }
    func isPromptLiked(_ id: String, memberID: String) -> Bool { state.likes.contains { $0.senderID == "me" && $0.recipientID == memberID && $0.promptID == id } }
    func isPhotoLiked(_ id: String, memberID: String) -> Bool {
        state.likes.contains { $0.senderID == "me" && $0.recipientID == memberID && $0.photoID == id }
    }
    func savedInterests(for memberID: String) -> [SavedInterest] {
        guard let member = member(memberID) else { return [] }
        return state.likes.reversed().filter { $0.senderID == "me" && $0.recipientID == memberID }
            .compactMap { $0.detail(in: member) }
    }
    func isMatched(_ id: String) -> Bool { state.matches.contains { $0.memberID == id && !blockedIDs.contains(id) } }
    @discardableResult
    private func mutate(_ action: () throws -> Void, feedback: String? = nil) -> Bool {
        do {
            try action()
            state = repository.snapshot()
            if let feedback { self.feedback = feedback; feedbackCount += 1 }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func like(_ id: String, promptID: String? = nil, photoID: String? = nil) {
        // A repeated tap must not add another record, announcement or haptic.
        guard !state.likes.contains(where: {
            $0.senderID == "me" && $0.recipientID == id && $0.promptID == promptID && $0.photoID == photoID
        }) else { return }
        let alreadyMatched = isMatched(id)
        guard mutate({ try repository.like(memberID: id, promptID: promptID, photoID: photoID) }) else { return }
        let saved = state.likes.last { $0.senderID == "me" && $0.recipientID == id && $0.promptID == promptID && $0.photoID == photoID }
        let detail = member(id).flatMap { saved?.detail(in: $0) }
        feedback = detail.map { "Saved \($0.title)" } ?? "Interest in \(member(id)?.name ?? "this person") saved"
        feedbackCount += 1
        if !alreadyMatched && isMatched(id) {
            presentedMatch = state.matches.first { $0.memberID == id }
            feedback = nil // The celebration presents the saved detail instead.
        }
    }
    func removeLike(_ id: String) { mutate({ repository.removeLike(memberID: id) }, feedback: "Like removed") }
    @discardableResult
    func pass(_ id: String) -> Bool { mutate({ try repository.pass(memberID: id) }, feedback: "Next introduction") }
    @discardableResult
    func undoPass(_ id: String) -> Bool { mutate({ try repository.undoPass(memberID: id) }, feedback: "Introduction restored") }
    func resetPasses() { mutate({ repository.resetPasses() }, feedback: "Passed profiles restored") }
    func block(_ id: String) {
        if mutate({ try repository.block(memberID: id) }, feedback: "Profile blocked in this demo") {
            let available = Set(state.conversations.map(\.id))
            conversationDrafts = conversationDrafts.filter { available.contains($0.key) }
            if presentedMatch?.memberID == id { presentedMatch = nil }
        }
    }
    func unblock(_ id: String) { mutate({ repository.unblock(memberID: id) }, feedback: "Profile unblocked") }
    func report(_ id: String, reason: ReportReason, details: String) -> Bool {
        mutate({ try repository.report(memberID: id, reason: reason, details: details) }, feedback: "Report saved locally. No report was sent.")
    }
    func draft(for conversationID: String) -> String { conversationDrafts[conversationID] ?? "" }
    func updateDraft(_ text: String, conversationID: String) {
        guard conversations.contains(where: { $0.id == conversationID }) else { return }
        conversationDrafts[conversationID] = text.isEmpty ? nil : text
    }
    func send(_ text: String, conversationID: String) -> Bool {
        guard mutate({ try repository.send(text: text, conversationID: conversationID) }) else { return false }
        conversationDrafts[conversationID] = nil
        return true
    }
    func markRead(_ id: String) { mutate { repository.markRead(conversationID: id) } }
    func updateProfile(_ profile: MemberProfile) -> Bool { mutate({ try repository.updateProfile(profile) }, feedback: "Profile updated") }
    func updateDiscovery(_ preferences: DiscoveryPreferences) -> Bool { mutate({ try repository.updateDiscovery(preferences) }, feedback: "Preferences updated") }
    func updatePrivacy(_ preferences: PrivacyPreferences) { mutate { repository.updatePrivacy(preferences) } }
    func updateNotifications(_ preferences: NotificationPreferences) { mutate { repository.updateNotifications(preferences) } }
    func completeOnboarding() -> Bool {
        for step in 0..<OnboardingDraft.stepCount {
            if let error = onboarding.validationError(step: step, now: now()) { errorMessage = error; onboardingStep = step; return false }
        }
        guard updateProfile(onboarding.profile(now: now())) else { return false }
        var preferences = state.discovery
        preferences.radiusMiles = onboarding.radiusMiles
        preferences.dating.genders = onboarding.genders
        guard updateDiscovery(preferences) else { return false }
        hasCompletedOnboarding = true
        isOnboarding = false
        feedback = nil
        return true
    }
}

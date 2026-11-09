import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    private var repository: any KindredRepository
    private let demoRepository: any KindredRepository
    private(set) var isDemoSession = true
    private(set) var isStaffOnlySession = false
    private var accountSession: BackendAccount.Session?
    private let persistLogin: Bool
    private var sessionRefresh: Task<BackendAccount.Session, Error>?
    private(set) var needsAccountRestore: Bool
    private(set) var isRestoringAccount = false
    private(set) var accountRestoreError: String?
    private let backend = BackendAccount()
    private var liveDiscoverMembers: [MemberProfile] = []
    private var discoveryCursor: BackendAccount.DiscoveryPage.Cursor?
    private var discoveryPageCount = 0
    private var discoveryRevision = 0
    var hasMoreDiscoveryProfiles: Bool { discoveryCursor != nil && !state.privacy.discoveryPaused }
    private var liveActivityMembers: [MemberProfile] = []
    private var activityRevision = 0
    private var pendingLikes: Set<String> = []
    private var dismissedLikedMembers: Set<String> = []
    private var loadedInitialActivity = false
    struct DiscoveryLikeAcknowledgement: Equatable {
        let memberID: String
        let id = UUID()
    }
    private(set) var discoveryLikeAcknowledgement: DiscoveryLikeAcknowledgement?
    private var pendingMessages: [String: (text: String, id: UUID)] = [:]
    private(set) var isSending: Set<String> = []
    private var pendingReads: Set<String> = []
    private(set) var loadingHistory: Set<String> = []
    private(set) var historyErrors: [String: String] = [:]
    private var pendingMatchMember: String?
    private(set) var activityLoadError: String?
    private(set) var unseenLikeIDs: Set<String> = []
    private var markingLikesSeen: Set<String> = []
    private(set) var isRefreshingDiscovery = false
    private(set) var discoveryLoadError: String?
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

    init(repository: (any KindredRepository)? = nil, now: @escaping () -> Date = Date.init, persistLogin: Bool = false) {
        self.now = now
        self.persistLogin = persistLogin
        needsAccountRestore = persistLogin
        let source = repository ?? InMemoryKindredRepository(now: now)
        self.repository = source
        self.demoRepository = source
        self.state = source.snapshot()
    }
    var blockedIDs: Set<String> { Set(state.blocks.map(\.memberID)) }
    func member(_ id: String) -> MemberProfile? {
        if id == "me" {
            var profile = state.currentProfile
            if !state.privacy.showCity { profile.city = "Location private"; profile.locationStatus = .home }
            return profile
        }
        return state.members.first { $0.id == id && !blockedIDs.contains(id) }
    }
    enum DiscoveryEmptyReason { case paused, filters, seenEveryone, unavailable }
    private var availableDiscoveryMembers: [MemberProfile] {
        let candidates = isDemoSession ? state.members : liveDiscoverMembers
        return candidates.filter { !blockedIDs.contains($0.id) && !isMatched($0.id) && !state.unmatchedIDs.contains($0.id) }
    }
    private var eligibleDiscoveryProfiles: [MemberProfile] {
        availableDiscoveryMembers.map { member in
            var profile = member
            if !isDemoSession { return profile }
            if let city = SearchCity.matching(profile.city) {
                profile.distanceMiles = state.discovery.searchCity.miles(to: city)
            } else {
                profile.distanceMiles = Int.max
            }
            return profile
        }.filter {
            state.discovery.dating.genders.contains($0.gender)
            && (state.discovery.dating.minimumAge...state.discovery.dating.maximumAge).contains($0.age)
            && $0.distanceMiles <= state.discovery.radiusMiles
        }
    }
    var discoveryProfiles: [MemberProfile] {
        guard !state.privacy.discoveryPaused else { return [] }
        let remaining = eligibleDiscoveryProfiles.filter { !state.passedIDs.contains($0.id) && !dismissedLikedMembers.contains($0.id) }
        return remaining.filter { !isLiked($0.id) } + remaining.filter { isLiked($0.id) }
    }
    var discoveryEmptyReason: DiscoveryEmptyReason? {
        if state.privacy.discoveryPaused { return .paused }
        guard discoveryProfiles.isEmpty else { return nil }
        if !eligibleDiscoveryProfiles.isEmpty { return .seenEveryone }
        return !availableDiscoveryMembers.isEmpty ? .filters : .unavailable
    }
    var outgoingProfiles: [MemberProfile] { state.members.filter { !blockedIDs.contains($0.id) && isLiked($0.id) } }
    var incomingProfiles: [MemberProfile] {
        state.members.filter { person in !blockedIDs.contains(person.id) && state.likes.contains { $0.senderID == person.id && $0.recipientID == "me" } }
    }
    var unseenLikesCount: Int {
        Set(state.likes.filter {
            $0.recipientID == "me" && unseenLikeIDs.contains($0.id)
                && !blockedIDs.contains($0.senderID) && !isMatched($0.senderID)
        }.map(\.senderID)).count
    }

    func markIncomingLikesSeen() async {
        guard let session = await activeAccountSession() else { return }
        let ids = unseenLikeIDs.subtracting(markingLikesSeen)
        guard !ids.isEmpty else { return }
        markingLikesSeen.formUnion(ids)
        defer {
            if accountSession?.loginID == session.loginID { markingLikesSeen.subtract(ids) }
        }
        do {
            try await backend.markLikesSeen(ids, session: session)
            guard accountSession?.loginID == session.loginID else { return }
            unseenLikeIDs.subtract(ids)
            await refreshActivity()
        } catch {
            // Keep the badge until the server acknowledges it.
        }
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
        if !isDemoSession {
            let key = id + ":" + (promptID.map { "prompt:" + $0 } ?? photoID.map { "photo:" + $0 } ?? "profile")
            guard let session = accountSession, pendingLikes.insert(key).inserted else { return }
            Task {
                defer { pendingLikes.remove(key) }
                guard let result = await performActivity(.like, target: id, promptID: promptID, photoID: photoID),
                      accountSession?.loginID == session.loginID else { return }
                if result.matched {
                    pendingMatchMember = id
                } else {
                    announceDiscoveryLike(id, promptID: promptID, photoID: photoID)
                }
                await refreshActivity()
            }
            return
        }
        let alreadyMatched = isMatched(id)
        guard mutate({ try repository.like(memberID: id, promptID: promptID, photoID: photoID) }) else { return }
        if !alreadyMatched && isMatched(id) {
            presentedMatch = state.matches.first { $0.memberID == id }
            feedback = nil
        } else {
            announceDiscoveryLike(id, promptID: promptID, photoID: photoID)
        }
    }

    private func announceDiscoveryLike(_ memberID: String, promptID: String?, photoID: String?) {
        let like = Like(id: "", senderID: "me", recipientID: memberID, promptID: promptID,
                        photoID: photoID, createdAt: now())
        let member = member(memberID)
        let detail = member.flatMap { like.detail(in: $0) }
        feedback = detail.map { "Saved \($0.title)" } ?? "Interest in \(member?.name ?? "this person") saved"
        feedbackCount += 1
        discoveryLikeAcknowledgement = .init(memberID: memberID)
    }

    func advancePastLikedMember(_ id: String) {
        if !isDemoSession { dismissedLikedMembers.insert(id) }
    }

    func removeLike(_ id: String) {
        if !isDemoSession {
            Task {
                if await performActivity(.removeLike, target: id) != nil { await refreshActivity() }
            }
            return
        }
        let message = isMatched(id) ? "Interest removed. Your connection and chat remain." : "Interest removed"
        mutate({ repository.removeLike(memberID: id) }, feedback: message)
    }
    @discardableResult
    func unmatch(_ id: String) -> Bool {
        guard mutate({ try repository.unmatch(memberID: id) }, feedback: "Connection ended in this demo") else { return false }
        let available = Set(state.conversations.map(\.id))
        conversationDrafts = conversationDrafts.filter { available.contains($0.key) }
        if presentedMatch?.memberID == id { presentedMatch = nil }
        return true
    }
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
    func endLiveConnection(_ id: String) async {
        if await performActivity(.unmatch, target: id) != nil {
            if presentedMatch?.memberID == id { presentedMatch = nil }
            await refreshActivity()
        }
    }

    func blockAccountMember(_ memberID: String) async {
        guard let session = await activeAccountSession(showError: true), let id = UUID(uuidString: memberID) else { return }
        do {
            try await backend.block(id, session: session)
            guard accountSession?.loginID == session.loginID else { return }
            mutate({ try repository.block(memberID: memberID) }, feedback: "Profile blocked")
            await refreshActivity()
            await refreshDiscovery()
        } catch { errorMessage = error.localizedDescription }
    }

    func unblockAccountMember(_ memberID: String) async {
        guard let session = await activeAccountSession(showError: true), let id = UUID(uuidString: memberID) else { return }
        do {
            try await backend.unblock(id, session: session)
            guard accountSession?.loginID == session.loginID else { return }
            mutate({ repository.unblock(memberID: memberID) }, feedback: "Profile unblocked")
            await refreshAccountBlocks()
            await refreshDiscovery()
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func refreshAccountBlocks() async -> Bool {
        guard let session = await activeAccountSession() else { return isDemoSession }
        do {
            let summaries = try await backend.loadBlockedMembers(session: session)
            guard accountSession?.loginID == session.loginID,
                  let accountRepository = repository as? InMemoryKindredRepository else { return false }
            accountRepository.replaceBlocks(summaries)
            state = repository.snapshot()
            return true
        } catch {
            return false
        }
    }

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
    func sendLive(_ text: String, conversationID: String) async -> Bool {
        guard let conversation = conversations.first(where: { $0.id == conversationID }),
              !text.trimmed.isEmpty, text.trimmed.count <= 2000,
              isSending.insert(conversationID).inserted else { return false }
        defer { isSending.remove(conversationID) }
        let id: UUID
        if let previous = pendingMessages[conversationID], previous.text == text { id = previous.id }
        else { id = UUID() }
        pendingMessages[conversationID] = (text, id)
        guard await performActivity(.send, target: conversation.memberID, text: text, messageID: id) != nil else { return false }
        pendingMessages[conversationID] = nil
        if draft(for: conversationID) == text { conversationDrafts[conversationID] = nil }
        await refreshActivity()
        return true
    }

    func submitLiveReport(_ id: String, reason: ReportReason, details: String) async -> Bool {
        await performActivity(.report, target: id, reason: reason, details: details) != nil
    }

    func loadOlderMessages(_ id: String) async {
        guard let session = await activeAccountSession(),
              let threadID = UUID(uuidString: id),
              let conversation = conversations.first(where: { $0.id == id }),
              conversation.hasOlderMessages == true,
              let first = conversation.messages.first,
              let messageID = UUID(uuidString: first.id),
              loadingHistory.insert(id).inserted else { return }
        historyErrors[id] = nil
        defer {
            if accountSession?.loginID == session.loginID { loadingHistory.remove(id) }
        }
        do {
            let page = try await backend.conversationHistory(threadID: threadID, before: messageID, session: session)
            guard !Task.isCancelled, accountSession?.loginID == session.loginID,
                  let accountRepository = repository as? InMemoryKindredRepository else { return }
            accountRepository.prependHistory(page, to: conversation)
            state = repository.snapshot()
        } catch {
            guard !Task.isCancelled, accountSession?.loginID == session.loginID else { return }
            if case BackendAccount.RequestError.rejected(401) = error {
                returnToWelcome()
                errorMessage = "Your session ended. Please sign in again."
            } else if case BackendAccount.RequestError.rejected(403) = error {
                await refreshActivity()
                if conversations.contains(where: { $0.id == id }) { historyErrors[id] = "Couldn’t load older messages. Try again." }
            } else {
                historyErrors[id] = "Couldn’t load older messages. Try again."
            }
        }
    }

    func markRead(_ id: String) {
        if isDemoSession { mutate { repository.markRead(conversationID: id) }; return }
        guard let conversation = conversations.first(where: { $0.id == id }),
              conversation.unreadCount > 0, let last = conversation.messages.last,
              let messageID = UUID(uuidString: last.id), pendingReads.insert(id).inserted else { return }
        Task {
            defer { pendingReads.remove(id) }
            if await performActivity(.read, target: conversation.memberID, readMessageID: messageID) != nil {
                await refreshActivity()
            }
        }
    }

    private func performActivity(_ kind: BackendAccount.ActivityAction.Kind, target: String,
                                 promptID: String? = nil, photoID: String? = nil, text: String? = nil,
                                 messageID: UUID? = nil, readMessageID: UUID? = nil,
                                 reason: ReportReason? = nil, details: String? = nil) async -> BackendAccount.ActivityResult? {
        guard let session = await activeAccountSession(showError: true), let targetID = UUID(uuidString: target) else { return nil }
        let action = BackendAccount.ActivityAction(action: kind, target: targetID, prompt_id: promptID, photo_id: photoID,
                                                   message_body: text, message_id: messageID, read_message_id: readMessageID,
                                                   report_reason: reason == .other ? "Other" : reason?.rawValue, report_details: details)
        do {
            let result = try await backend.perform(action, session: session)
            guard accountSession?.loginID == session.loginID else { return nil }
            return result
        } catch {
            if accountSession?.loginID == session.loginID { errorMessage = error.localizedDescription }
            return nil
        }
    }

    func refreshActivity() async {
        guard let session = await activeAccountSession(), hasCompletedOnboarding else { return }
        activityRevision += 1
        let revision = activityRevision
        do {
            let activity = try await backend.loadActivity(session: session)
            guard !Task.isCancelled, revision == activityRevision, accountSession?.loginID == session.loginID,
                  let accountRepository = repository as? InMemoryKindredRepository else { return }
            activityLoadError = nil
            unseenLikeIDs = activity.unseenLikeIDs ?? []
            if !loadedInitialActivity {
                let sent = activity.likes.filter { $0.senderID == "me" }.map(\.recipientID)
                dismissedLikedMembers.formUnion(sent.filter { memberID in
                    !pendingLikes.contains(where: { $0.hasPrefix(memberID + ":") })
                        && discoveryLikeAcknowledgement?.memberID != memberID
                })
                loadedInitialActivity = true
            }
            liveActivityMembers = activity.members
            accountRepository.replaceActivity(activity)
            mergeLiveMembers(in: accountRepository)
            let available = Set(state.conversations.map(\.id))
            conversationDrafts = conversationDrafts.filter { available.contains($0.key) }
            pendingMessages = pendingMessages.filter { available.contains($0.key) }
            historyErrors = historyErrors.filter { available.contains($0.key) }
            if let member = pendingMatchMember,
               let match = state.matches.first(where: { $0.memberID == member }) {
                pendingMatchMember = nil
                presentedMatch = match
                feedback = nil
            }
        } catch {
            guard !Task.isCancelled, revision == activityRevision, accountSession?.loginID == session.loginID else { return }
            if case BackendAccount.RequestError.rejected(401) = error {
                returnToWelcome()
                errorMessage = "Your session ended. Please sign in again."
            } else {
                activityLoadError = error.localizedDescription
            }
        }
    }

    private func mergeLiveMembers(in accountRepository: InMemoryKindredRepository) {
        let discovered = Set(liveDiscoverMembers.map(\.id))
        accountRepository.replaceMembers(liveDiscoverMembers + liveActivityMembers.filter { !discovered.contains($0.id) })
        state = repository.snapshot()
    }
    func updateProfile(_ profile: MemberProfile) -> Bool { mutate({ try repository.updateProfile(profile) }, feedback: "Profile updated") }
    func updateDiscovery(_ preferences: DiscoveryPreferences) -> Bool { mutate({ try repository.updateDiscovery(preferences) }, feedback: "Preferences updated") }
    func updatePrivacy(_ preferences: PrivacyPreferences) { mutate { repository.updatePrivacy(preferences) } }
    func updateNotifications(_ preferences: NotificationPreferences) { mutate { repository.updateNotifications(preferences) } }
    func startDemoOnboarding() {
        if !isDemoSession {
            returnToWelcome()
            onboarding = OnboardingDraft()
            onboardingStep = 0
        }
        isOnboarding = true
    }
    func restoreAccount() async {
        guard needsAccountRestore, !isRestoringAccount else { return }
        isRestoringAccount = true
        accountRestoreError = nil
        defer { isRestoringAccount = false }
        do {
            guard var session = try AccountKeychain.load(BackendAccount.Session.self, for: .session) else {
                needsAccountRestore = false
                return
            }
            // Confirm the saved login is still valid, even if its access token hasn't expired.
            session = try await backend.refresh(session: session)
            guard needsAccountRestore else { return }
            try AccountKeychain.save(session, for: .session)
            try Task.checkCancellation()
            let profile = try await backend.loadDiscoveryProfile(session: session)
            let staffOnly = profile == nil ? (try? await backend.isSafetyReviewer(session: session)) == true : false
            let name: String
            if let profile { name = profile.profile.name }
            else { name = try await backend.loadProfile(session: session) }
            try Task.checkCancellation()
            guard needsAccountRestore else { return }
            openAccount(displayName: name, session: session, profile: profile, staffOnly: staffOnly)
            needsAccountRestore = false
        } catch let error as BackendAccount.RequestError where error.invalidSession {
            try? AccountKeychain.remove(.session)
            needsAccountRestore = false
        } catch {
            if !Task.isCancelled { accountRestoreError = error.localizedDescription }
        }
    }

    func forgetSavedLogin() {
        do {
            try AccountKeychain.remove(.session)
            needsAccountRestore = false
            accountRestoreError = nil
        } catch { accountRestoreError = error.localizedDescription }
    }

    func maintainAccountSession() async {
        while !Task.isCancelled {
            if needsAccountRestore && accountRestoreError == nil { await restoreAccount() }
            _ = await activeAccountSession()
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
        }
    }

    private func activeAccountSession(showError: Bool = false) async -> BackendAccount.Session? {
        do { return try await refreshAccountSessionIfNeeded() }
        catch {
            if showError && !Task.isCancelled { errorMessage = error.localizedDescription }
            return nil
        }
    }

    private func refreshAccountSessionIfNeeded() async throws -> BackendAccount.Session? {
        guard let session = accountSession else { return nil }
        guard session.expiresAt.timeIntervalSince(now()) <= 60 else { return session }
        let refresh: Task<BackendAccount.Session, Error>
        if let sessionRefresh { refresh = sessionRefresh }
        else {
            let api = backend
            refresh = Task { try await api.refresh(session: session) }
            sessionRefresh = refresh
        }
        do {
            let updated = try await refresh.value
            guard accountSession?.loginID == session.loginID else { return nil }
            if accountSession?.access_token == session.access_token {
                accountSession = updated
                sessionRefresh = nil
                if persistLogin {
                    do { try AccountKeychain.save(updated, for: .session) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            return accountSession
        } catch {
            guard accountSession?.loginID == session.loginID else { return nil }
            sessionRefresh = nil
            if let rejected = error as? BackendAccount.RequestError, rejected.invalidSession {
                returnToWelcome()
                errorMessage = "Your session ended. Please sign in again."
            } else if session.expiresAt > now() {
                return session
            }
            throw error
        }
    }

    func passwordWasReset(for userID: UUID) {
        if accountSession?.user.id == userID {
            returnToWelcome()
        } else if persistLogin,
                  let saved = try? AccountKeychain.load(BackendAccount.Session.self, for: .session),
                  saved.user.id == userID {
            forgetSavedLogin()
        }
        feedback = "Password updated. Sign in with your new password."
        feedbackCount += 1
    }

    func signOutAccount() async throws {
        guard let session = accountSession else {
            returnToWelcome()
            return
        }
        let active = try await refreshAccountSessionIfNeeded() ?? session
        guard accountSession?.loginID == session.loginID else { return }
        try await backend.signOut(session: active)
        guard accountSession?.loginID == session.loginID else { return }
        if persistLogin { try AccountKeychain.remove(.session) }
        returnToWelcome()
    }

    var accountEmail: String? { accountSession?.user.email }

    func deleteAccount(password: String) async throws {
        guard let session = accountSession else { throw KindredError.invalid("Sign in to delete your account.") }
        try await backend.deleteAccount(session: session, password: password)
        guard accountSession?.loginID == session.loginID else { return }
        returnToWelcome()
    }

    func returnToWelcome() {
        hasCompletedOnboarding = false
        isOnboarding = false
        if !isDemoSession {
            accountSession = nil
            isStaffOnlySession = false
            sessionRefresh?.cancel()
            sessionRefresh = nil
            if persistLogin { try? AccountKeychain.remove(.session) }
            liveDiscoverMembers = []
            discoveryCursor = nil
            discoveryPageCount = 0
            discoveryRevision += 1
            liveActivityMembers = []
            pendingLikes.removeAll()
            dismissedLikedMembers.removeAll()
            loadedInitialActivity = false
            discoveryLikeAcknowledgement = nil
            pendingMessages.removeAll()
            pendingReads.removeAll()
            loadingHistory.removeAll()
            historyErrors.removeAll()
            isSending.removeAll()
            pendingMatchMember = nil
            activityLoadError = nil
            unseenLikeIDs.removeAll()
            markingLikesSeen.removeAll()
            isRefreshingDiscovery = false
            discoveryLoadError = nil
            repository = demoRepository
            state = demoRepository.snapshot()
            isDemoSession = true
            conversationDrafts.removeAll()
            presentedMatch = nil
            feedback = nil
            errorMessage = nil
            onboarding = OnboardingDraft()
            onboardingStep = 0
        }
    }
    func startAccountOnboarding(displayName: String) {
        isDemoSession = false
        onboarding = OnboardingDraft()
        onboarding.name = displayName
        onboarding.birthDate = now()
        onboardingStep = 0
        isOnboarding = true
    }
    func openAccount(displayName: String, session: BackendAccount.Session, profile: BackendAccount.DiscoveryProfile?,
                     staffOnly: Bool = false) {
        startAccountOnboarding(displayName: displayName)
        accountSession = session
        if persistLogin {
            do { try AccountKeychain.save(session, for: .session) }
            catch { errorMessage = error.localizedDescription }
        }
        isStaffOnlySession = staffOnly
        if staffOnly { isOnboarding = false }
        else if let profile { enterAccount(profile) }
    }

    func canReviewSafetyReports() async -> Bool {
        guard let session = await activeAccountSession() else { return false }
        let allowed = (try? await backend.isSafetyReviewer(session: session)) == true
        return allowed && accountSession?.loginID == session.loginID
    }

    func loadSafetyReports(reviewed: Bool, offset: Int) async throws -> [BackendAccount.SafetyReport] {
        guard let session = try await refreshAccountSessionIfNeeded() else { throw KindredError.unavailable }
        let reports = try await backend.loadSafetyQueue(reviewed: reviewed, offset: offset, session: session)
        guard accountSession?.loginID == session.loginID else { throw KindredError.unavailable }
        return reports
    }

    func reviewSafetyReport(_ id: UUID, action: BackendAccount.SafetyAction, note: String? = nil) async throws {
        guard let session = try await refreshAccountSessionIfNeeded() else { throw KindredError.unavailable }
        try await backend.reviewSafetyReport(id, action: action, note: note, session: session)
    }

    private func enterAccount(_ row: BackendAccount.DiscoveryProfile) {
        let accountState = SessionSnapshot(currentProfile: row.profile, members: [], likes: [], matches: [],
                                           conversations: [], discovery: row.preferences, privacy: row.privacy)
        repository = InMemoryKindredRepository(state: accountState, now: now)
        state = accountState
        conversationDrafts.removeAll()
        presentedMatch = nil
        hasCompletedOnboarding = true
        isOnboarding = false
        feedback = nil
    }

    func refreshDiscovery(reset: Bool = false) async {
        await loadDiscoveryPages(append: false, reset: reset)
    }

    func loadMoreDiscovery() async {
        guard hasMoreDiscoveryProfiles else { return }
        await loadDiscoveryPages(append: true, reset: false)
    }

    private func loadDiscoveryPages(append: Bool, reset: Bool) async {
        guard let session = await activeAccountSession(), hasCompletedOnboarding,
              let accountRepository = repository as? InMemoryKindredRepository,
              reset || !isRefreshingDiscovery else { return }
        let pageTarget = max(discoveryPageCount, 1)
        if reset {
            liveDiscoverMembers = []
            discoveryCursor = nil
            discoveryPageCount = 0
        }
        discoveryRevision += 1
        let revision = discoveryRevision
        isRefreshingDiscovery = true
        discoveryLoadError = nil
        if reset { mergeLiveMembers(in: accountRepository) }
        defer {
            if discoveryRevision == revision { isRefreshingDiscovery = false }
        }
        do {
            var members = append ? liveDiscoverMembers : []
            var cursor = append ? discoveryCursor : nil
            var pageCount = append ? discoveryPageCount : 0
            var seen = Set(members.map(\.id))
            repeat {
                let page = try await backend.discover(after: cursor, session: session)
                guard !Task.isCancelled, discoveryRevision == revision,
                      accountSession?.loginID == session.loginID else { return }
                members += page.profiles.filter { seen.insert($0.id).inserted }
                cursor = page.next
                pageCount += 1
            } while !append && !reset && pageCount < pageTarget && cursor != nil
            liveDiscoverMembers = members
            discoveryCursor = cursor
            discoveryPageCount = pageCount
            mergeLiveMembers(in: accountRepository)
        } catch {
            guard !Task.isCancelled, discoveryRevision == revision, accountSession?.loginID == session.loginID else { return }
            discoveryLoadError = error.localizedDescription
        }
    }

    func finishOnboarding() async -> Bool {
        if isDemoSession { return completeOnboarding() }
        guard let session = await activeAccountSession(showError: true) else { return false }
        guard let profile = validatedOnboardingProfile() else { return false }
        let row = BackendAccount.DiscoveryProfile(user_id: session.user.id, profile: profile,
                                                  preferences: onboardingPreferences(), privacy: .init())
        do {
            try await backend.saveDiscoveryProfile(row, session: session)
            guard accountSession?.loginID == session.loginID else { return false }
            enterAccount(row)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var discoverySearchLocation: String {
        state.discovery.useHomeCityForSearch ? state.currentProfile.city : state.discovery.searchCity.rawValue
    }

    func saveProfileChanges(_ profile: MemberProfile) async -> Bool {
        guard profile.validationIssues.isEmpty else { return false }
        var normalized = profile
        normalized.name = profile.name.trimmed
        normalized.city = profile.city.trimmed
        return await saveAccountChanges(.init(profile: normalized), feedback: "Profile updated")
    }

    func saveDiscoveryChanges(_ preferences: DiscoveryPreferences) async -> Bool {
        guard preferences.isValid else {
            errorMessage = "Choose who you’d like to meet and a valid age range and distance."
            return false
        }
        return await saveAccountChanges(.init(preferences: preferences), feedback: "Preferences updated")
    }

    func savePrivacyChanges(_ privacy: PrivacyPreferences) async -> Bool {
        await saveAccountChanges(.init(privacy: privacy), feedback: nil)
    }

    private func saveAccountChanges(_ change: BackendAccount.SettingsChange, feedback: String?) async -> Bool {
        guard let session = await activeAccountSession(showError: true) else { return false }
        do {
            try await backend.saveSettings(change, session: session)
            guard accountSession?.loginID == session.loginID else { return false }
            let previousProfile = state.currentProfile
            let previousDiscovery = state.discovery
            let wasPaused = state.privacy.discoveryPaused
            let saved = mutate({
                if let profile = change.profile { try repository.updateProfile(profile) }
                if let preferences = change.preferences { try repository.updateDiscovery(preferences) }
                if let privacy = change.privacy { repository.updatePrivacy(privacy) }
            }, feedback: feedback)
            if saved && (previousDiscovery != state.discovery || wasPaused != state.privacy.discoveryPaused
                || previousProfile.city != state.currentProfile.city || previousProfile.age != state.currentProfile.age
                || previousProfile.gender != state.currentProfile.gender) {
                await refreshDiscovery(reset: true)
            }
            return saved
        } catch {
            if accountSession?.loginID == session.loginID { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func validatedOnboardingProfile() -> MemberProfile? {
        for step in 0..<OnboardingDraft.stepCount {
            if let error = onboarding.validationError(step: step, now: now()) {
                errorMessage = error
                onboardingStep = step
                return nil
            }
        }
        return onboarding.profile(now: now())
    }

    private func onboardingPreferences() -> DiscoveryPreferences {
        var preferences = isDemoSession ? state.discovery : .defaults(forHomeCity: onboarding.city)
        preferences.radiusMiles = onboarding.radiusMiles
        if isDemoSession { preferences.searchCity = SearchCity.matching(onboarding.city) ?? .chicago }
        preferences.dating.genders = onboarding.genders
        return preferences
    }

    func completeOnboarding() -> Bool {
        guard accountSession == nil, let profile = validatedOnboardingProfile() else { return false }
        let preferences = onboardingPreferences()
        if isDemoSession {
            guard updateProfile(profile), updateDiscovery(preferences) else { return false }
            hasCompletedOnboarding = true
            isOnboarding = false
            feedback = nil
        } else {
            enterAccount(.init(user_id: UUID(), profile: profile, preferences: preferences, privacy: .init()))
        }
        return true
    }
}

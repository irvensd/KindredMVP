import Foundation
import Testing
@testable import Kindred

@MainActor
struct KindredTests {
    let now = Date(timeIntervalSince1970: 1_792_022_400) // 2026-10-15 UTC
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day))! }
    func store() -> AppStore { AppStore(now: { now }) }
    func validDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.acknowledgedAdult = true; draft.name = "Alex"; draft.birthDate = date(1998, 2, 2)
        draft.gender = .male; draft.genders = [.female, .male]; draft.city = "Chicago"
        draft.intention = .relationship; draft.interests = [.books, .cooking, .hiking]
        draft.prompts = DemoData.people[0].prompts
        draft.photos = DemoData.people[0].photos
        return draft
    }
    @Test func profileValidationIdentifiesFieldsAndPreservesOptionalBlanks() {
        let s = store(); var p = s.state.currentProfile
        p.name = " "; p.city = "x"; p.bio = String(repeating: "a", count: 501)
        p.faith.meaning = String(repeating: "a", count: 301)
        p.prompts[1].answer = "Hi"; p.photos = []
        #expect(p.validationIssues.map(\.id) == ["name", "city", "bio", "faith", "prompt-" + p.prompts[1].id, "photos"])
        #expect(!s.updateProfile(p)); #expect(s.state.currentProfile.name == "Alex")
        p.name = String(repeating: "a", count: 40); p.city = "NY"
        p.bio = String(repeating: "a", count: 500); p.faith.meaning = String(repeating: "a", count: 300)
        p.prompts[0].answer = "     "; p.prompts[1].answer = "Hello"; p.prompts[2].answer = String(repeating: "a", count: 240)
        p.photos = s.state.currentProfile.photos
        #expect(p.validationIssues.isEmpty); #expect(s.updateProfile(p))
        p.name += "a"; p.city = String(repeating: "a", count: 61); p.prompts[2].answer += "a"
        #expect(p.validationIssues.map(\.id) == ["name", "city", "prompt-" + p.prompts[2].id])
    }

    @Test func unmatchClearsConnectionWithoutBlockingOrImmediateRematch() {
        let s = store(); s.like("amara")
        s.updateDraft("Amara draft", conversationID: "chat-amara")
        s.updateDraft("Eli draft", conversationID: "chat-eli")
        s.removeLike("amara")
        #expect(s.isMatched("amara"))
        #expect(s.draft(for: "chat-amara") == "Amara draft")
        #expect(s.unmatch("amara"))
        #expect(!s.isMatched("amara")); #expect(!s.isLiked("amara"))
        #expect(!s.incomingProfiles.contains { $0.id == "amara" })
        #expect(!s.conversations.contains { $0.memberID == "amara" })
        #expect(s.draft(for: "chat-amara").isEmpty)
        #expect(s.draft(for: "chat-eli") == "Eli draft")
        #expect(s.presentedMatch == nil); #expect(!s.blockedIDs.contains("amara"))
        #expect(s.member("amara") != nil)
        s.updateDraft("Stale draft", conversationID: "chat-amara")
        #expect(s.draft(for: "chat-amara").isEmpty)
        #expect(!s.send("Stale message", conversationID: "chat-amara"))
        s.like("amara")
        #expect(!s.isMatched("amara")); #expect(s.presentedMatch == nil)
        #expect(!s.unmatch("amara"))
        #expect(s.isLiked("amara"))
    }
    @Test func conversationDraftsAreSeparateAndSessionOnly() {
        let s = store(); s.like("amara")
        let originalMessages = s.conversations.first { $0.id == "chat-eli" }!.messages
        s.updateDraft("  Hello Eli\nA question…  ", conversationID: "chat-eli")
        s.updateDraft("Hello Amara", conversationID: "chat-amara")
        #expect(s.draft(for: "chat-eli") == "  Hello Eli\nA question…  ")
        #expect(s.draft(for: "chat-amara") == "Hello Amara")
        #expect(s.conversations.first { $0.id == "chat-eli" }!.messages == originalMessages)
        #expect(store().draft(for: "chat-eli").isEmpty)
        s.updateDraft("", conversationID: "chat-eli")
        #expect(s.draft(for: "chat-eli").isEmpty)
        #expect(s.draft(for: "chat-amara") == "Hello Amara")
    }
    @Test func onlySuccessfulSendClearsItsDraft() {
        let s = store(); s.like("amara")
        s.updateDraft("Hello", conversationID: "chat-amara")
        let tooLong = String(repeating: "a", count: 2001)
        s.updateDraft(tooLong, conversationID: "chat-eli")
        #expect(!s.send(tooLong, conversationID: "chat-eli"))
        #expect(s.draft(for: "chat-eli") == tooLong)
        s.updateDraft("Hi Eli", conversationID: "chat-eli")
        #expect(s.send(s.draft(for: "chat-eli"), conversationID: "chat-eli"))
        #expect(s.draft(for: "chat-eli").isEmpty)
        #expect(s.draft(for: "chat-amara") == "Hello")
    }
    @Test func blockingClearsOnlyRemovedConversationDrafts() {
        let s = store(); s.like("amara")
        s.updateDraft("Hello", conversationID: "chat-amara")
        s.updateDraft("Hi Eli", conversationID: "chat-eli")
        s.block("eli")
        #expect(s.draft(for: "chat-eli").isEmpty)
        #expect(s.draft(for: "chat-amara") == "Hello")
        s.updateDraft("Stale view", conversationID: "chat-eli")
        #expect(s.draft(for: "chat-eli").isEmpty)
        s.unblock("eli")
        #expect(s.draft(for: "chat-eli").isEmpty)
    }

    @Test func photoInterestUsesRecipientAndPhotoNotJustSharedAsset() {
        let s = store()
        s.like("amara", photoID: "weekend")
        #expect(s.isPhotoLiked("weekend", memberID: "amara"))
        #expect(!s.isPhotoLiked("weekend", memberID: "eli"))
        #expect(!s.isPhotoLiked("amara", memberID: "amara"))
        #expect(s.savedInterests(for: "amara").first?.title == "Amara’s photo 2")
        #expect(s.savedInterests(for: "amara").first?.photo?.id == "weekend")
        #expect(s.presentedMatch?.memberID == "amara")
        s.presentedMatch = nil
        let feedbackCount = s.feedbackCount
        s.like("amara", photoID: "weekend")
        #expect(s.feedbackCount == feedbackCount)
        #expect(s.presentedMatch == nil)
        s.like("eli", photoID: "weekend")
        #expect(s.feedback == "Saved Eli’s photo 2")
        #expect(s.isPhotoLiked("weekend", memberID: "eli"))
    }
    @Test func personalLikesStayDistinctWithoutDuplicatingMatchOrChat() {
        let s = store()
        s.like("amara", photoID: "amara")
        s.presentedMatch = nil
        s.like("amara", photoID: "weekend")
        s.like("amara", promptID: "amara-0")
        s.like("amara", promptID: "amara-0")
        s.like("amara")
        #expect(s.state.likes.filter { $0.senderID == "me" && $0.recipientID == "amara" }.count == 4)
        #expect(s.outgoingProfiles.count == 1)
        #expect(s.state.matches.filter { $0.memberID == "amara" }.count == 1)
        #expect(s.conversations.filter { $0.memberID == "amara" }.count == 1)
        #expect(s.presentedMatch == nil)
        #expect(s.savedInterests(for: "amara").count == 3)
        #expect(s.savedInterests(for: "amara").first?.answer == DemoData.people[0].prompts[0].answer)
        #expect(s.conversations.first { $0.memberID == "amara" }?.messages.isEmpty == true)
        s.removeLike("amara")
        #expect(!s.isPhotoLiked("weekend", memberID: "amara"))
        #expect(!s.isPromptLiked("amara-0", memberID: "amara"))
        #expect(s.savedInterests(for: "amara").isEmpty)
        #expect(s.isMatched("amara"))
    }
    @Test func invalidPhotoOrMixedTargetCannotSaveOrMatch() {
        for target in ["missing", "eli"] {
            let s = store(); s.like("amara", photoID: target)
            #expect(!s.isLiked("amara"))
            #expect(s.presentedMatch == nil)
            #expect(s.feedbackCount == 0)
            #expect(s.errorMessage != nil)
        }
        let s = store(); s.like("amara", promptID: "amara-0", photoID: "amara")
        #expect(!s.isLiked("amara"))
        #expect(s.errorMessage != nil)
    }
    @Test func answerFeedbackNamesMemberAndQuestionAndDoesNotRepeat() {
        let s = store(); s.like("eli", promptID: "eli-0")
        #expect(s.feedback == "Saved Eli’s answer to “My ideal Sabbath afternoon…”")
        #expect(s.savedInterests(for: "eli").first?.answer == "Cooking enough for whoever drops by after church.")
        let feedbackCount = s.feedbackCount
        s.like("eli", promptID: "eli-0")
        #expect(s.feedbackCount == feedbackCount)
        s.block("eli")
        #expect(s.savedInterests(for: "eli").isEmpty)
        s.like("eli", photoID: "eli")
        #expect(!s.isPhotoLiked("eli", memberID: "eli"))
        #expect(s.errorMessage != nil)
    }
    @Test func verticalStartCannotTurnIntoAProfileSwipe() {
        var swipe = DiscoverySwipe()
        swipe.update(CGSize(width: 3, height: 20), width: 354, isLiked: false)
        swipe.update(CGSize(width: -150, height: 50), width: 354, isLiked: false)
        #expect(swipe.axis == .vertical)
        #expect(swipe.translation == 0)
        #expect(swipe.action(at: CGSize(width: -150, height: 50), predicted: CGSize(width: -300, height: 50), velocity: CGSize(width: -900, height: 0), width: 354, isLiked: false) == nil)
    }
    @Test func ambiguousDiagonalsAndTurnsFavorScrolling() {
        var swipe = DiscoverySwipe()
        swipe.update(CGSize(width: 20, height: 20), width: 354, isLiked: false)
        #expect(swipe.axis == .undecided)
        swipe.update(CGSize(width: 30, height: 30), width: 354, isLiked: false)
        swipe.update(CGSize(width: 160, height: 40), width: 354, isLiked: false)
        #expect(swipe.axis == .vertical)
        var turn = DiscoverySwipe()
        turn.update(CGSize(width: 25, height: 2), width: 354, isLiked: false)
        turn.update(CGSize(width: 30, height: 60), width: 354, isLiked: false)
        turn.update(CGSize(width: 160, height: 65), width: 354, isLiked: false)
        #expect(turn.axis == .vertical)
        #expect(turn.offset(width: 354) == 0)
    }
    @Test func releaseDistanceIsConsistentAcrossPhotoWidths() {
        for width: CGFloat in [280, 354, 430, 600] {
            for direction: CGFloat in [-1, 1] {
                var swipe = DiscoverySwipe()
                let threshold = DiscoverySwipe.threshold(width: width)
                let justShort = CGSize(width: direction * (threshold - 1), height: 0)
                swipe.update(justShort, width: width, isLiked: false)
                #expect(!swipe.isReady(width: width, isLiked: false))
                #expect(swipe.action(at: justShort, predicted: justShort, velocity: .zero, width: width, isLiked: false) == nil)
                let full = CGSize(width: direction * threshold, height: 0)
                swipe.update(full, width: width, isLiked: false)
                #expect(swipe.isReady(width: width, isLiked: false))
                #expect(swipe.action(at: full, predicted: full, velocity: .zero, width: width, isLiked: false) == (direction < 0 ? .next : .interested))
            }
        }
    }
    @Test func releaseFeedbackAgreesWithDiagonalReleaseDecision() {
        var swipe = DiscoverySwipe()
        swipe.update(CGSize(width: 20, height: 1), width: 354, isLiked: false)
        let diagonal = CGSize(width: 100, height: 90)
        swipe.update(diagonal, width: 354, isLiked: false)
        #expect(!swipe.isReady(width: 354, isLiked: false))
        #expect(!swipe.didReachThreshold)
        #expect(swipe.action(at: diagonal, predicted: diagonal, velocity: .zero, width: 354, isLiked: false) == nil)
    }
    @Test func shortFlickRequiresTravelSpeedAndMatchingDirection() {
        for direction: CGFloat in [-1, 1] {
            var swipe = DiscoverySwipe()
            let travel = CGSize(width: direction * 65, height: 5)
            let prediction = CGSize(width: direction * 180, height: 5)
            swipe.update(travel, width: 354, isLiked: false)
            #expect(swipe.action(at: travel, predicted: prediction, velocity: CGSize(width: direction * 800, height: 0), width: 354, isLiked: false) == (direction < 0 ? .next : .interested))
            #expect(swipe.action(at: travel, predicted: prediction, velocity: CGSize(width: direction * 200, height: 0), width: 354, isLiked: false) == nil)
            #expect(swipe.action(at: travel, predicted: prediction, velocity: CGSize(width: direction * 499, height: 0), width: 354, isLiked: false) == nil)
            #expect(swipe.action(at: travel, predicted: prediction, velocity: CGSize(width: direction * 500, height: 0), width: 354, isLiked: false) == (direction < 0 ? .next : .interested))
            #expect(swipe.action(at: travel, predicted: prediction, velocity: CGSize(width: -direction * 800, height: 0), width: 354, isLiked: false) == nil)
            #expect(swipe.action(at: CGSize(width: direction * 25, height: 0), predicted: prediction, velocity: CGSize(width: direction * 1200, height: 0), width: 354, isLiked: false) == nil)
            #expect(swipe.action(at: travel, predicted: CGSize(width: -direction * 180, height: 0), velocity: CGSize(width: direction * 800, height: 0), width: 354, isLiked: false) == nil)
        }
    }
    @Test func returningBelowThresholdCancelsAndHapticOnlyArmsOnce() {
        var swipe = DiscoverySwipe()
        swipe.update(CGSize(width: 110, height: 2), width: 354, isLiked: false)
        #expect(swipe.didReachThreshold)
        let returned = CGSize(width: 30, height: 0)
        swipe.update(returned, width: 354, isLiked: false)
        #expect(!swipe.isReady(width: 354, isLiked: false))
        #expect(swipe.didReachThreshold)
        #expect(swipe.action(at: returned, predicted: returned, velocity: .zero, width: 354, isLiked: false) == nil)
        swipe = DiscoverySwipe()
        #expect(swipe.offset(width: 354) == 0)
        #expect(!swipe.didReachThreshold)
    }
    @Test func alreadyLikedRightSwipeDoesNothingButLeftStillWorks() {
        var swipe = DiscoverySwipe()
        swipe.update(CGSize(width: 150, height: 0), width: 354, isLiked: true)
        #expect(!swipe.didReachThreshold)
        #expect(swipe.action(at: CGSize(width: 150, height: 0), predicted: CGSize(width: 200, height: 0), velocity: .zero, width: 354, isLiked: true) == nil)
        swipe.update(CGSize(width: -150, height: 0), width: 354, isLiked: true)
        #expect(swipe.didReachThreshold)
        #expect(swipe.action(at: CGSize(width: -150, height: 0), predicted: CGSize(width: -200, height: 0), velocity: .zero, width: 354, isLiked: true) == .next)
    }
    @Test func photoMovementHasContinuousBoundedResistance() {
        var previous: CGFloat = 0
        for distance: CGFloat in [0, 15, 40, 90, 180, 500, 2000] {
            var right = DiscoverySwipe(), left = DiscoverySwipe()
            right.update(CGSize(width: distance, height: 0), width: 354, isLiked: false)
            left.update(CGSize(width: -distance, height: 0), width: 354, isLiked: false)
            let offset = right.offset(width: 354)
            #expect(offset >= previous && offset < 88)
            #expect(abs(offset + left.offset(width: 354)) < 0.001)
            previous = offset
        }
    }
    @Test func newMutualConversationAppearsBeforeOlderMessages() {
        let s = store()
        s.like("amara")
        #expect(s.conversations.first?.memberID == "amara")
    }
    @Test func matchCelebrationIsOncePerNewMatchAndBlockClearsIt() {
        let s = store()
        s.like("eli"); #expect(s.presentedMatch == nil)
        s.like("amara"); #expect(s.presentedMatch?.memberID == "amara")
        s.presentedMatch = nil
        s.like("amara", promptID: "amara-0"); s.removeLike("amara"); s.like("amara")
        #expect(s.presentedMatch == nil)
        #expect(s.state.matches.filter { $0.memberID == "amara" }.count == 1)
        #expect(s.conversations.filter { $0.memberID == "amara" }.count == 1)
        s.like("june"); #expect(s.presentedMatch?.memberID == "june")
        s.block("june"); #expect(s.presentedMatch == nil)
        #expect(!s.isMatched("june"))
    }
    @Test func promptStateIsScopedToItsMemberEvenWithSharedPromptIDs() {
        var snapshot = DemoData.snapshot(now: now)
        snapshot.members[0].prompts[0].id = "shared-question"
        snapshot.members[1].prompts[0].id = "shared-question"
        let s = AppStore(repository: InMemoryKindredRepository(state: snapshot, now: { now }))
        s.like("amara", promptID: "shared-question")
        #expect(s.isPromptLiked("shared-question", memberID: "amara"))
        #expect(!s.isPromptLiked("shared-question", memberID: "eli"))
        #expect(!s.isLiked("eli"))
    }
    @Test func matchingReusesAnExistingConversationAndItsMessages() {
        var snapshot = DemoData.snapshot(now: now)
        snapshot.matches = []
        snapshot.likes.append(.init(id: "incoming-eli", senderID: "eli", recipientID: "me", promptID: nil, createdAt: now))
        let s = AppStore(repository: InMemoryKindredRepository(state: snapshot, now: { now }))
        s.like("eli")
        #expect(s.conversations.count == 1)
        #expect(s.conversations[0].messages.count == 3)
        #expect(s.presentedMatch?.memberID == "eli")
    }
    @Test func preferencesPersistInSessionAndResetWithFreshRepository() {
        let repo = InMemoryKindredRepository(now: { now })
        let s = AppStore(repository: repo)
        var preferences = s.state.discovery
        preferences.dating.genders = [.male]; preferences.radiusMiles = 150
        #expect(s.updateDiscovery(preferences))
        let reopened = AppStore(repository: repo)
        #expect(reopened.state.discovery == preferences)
        #expect(reopened.discoveryProfiles.map(\.id) == ["eli", "rowan"])
        #expect(store().state.discovery == DiscoveryPreferences())
    }
    @Test func dateGroupsUseCalendarBoundariesAndPreviewsNameOutgoingMessages() {
        let first = date(2026, 10, 12).addingTimeInterval(86340)
        let second = date(2026, 10, 13).addingTimeInterval(60)
        let c = Conversation(id: "test", memberID: "eli", messages: [
            .init(id: "1", senderID: "eli", text: "Hello", createdAt: first),
            .init(id: "2", senderID: "me", text: "Hi there", createdAt: second),
            .init(id: "3", senderID: "me", text: "How are you?", createdAt: second.addingTimeInterval(60))], unreadCount: 0)
        #expect(c.days(calendar: calendar).map { $0.messages.count } == [1, 2])
        #expect(c.preview == "You: How are you?")
        var local = calendar; local.timeZone = TimeZone(secondsFromGMT: -21600)!
        #expect(c.days(calendar: local).count == 1)
    }
    @Test func optionalStoryChecklistAndStartersDoNotRequirePrivateDetails() {
        var p = store().state.currentProfile
        p.bio = ""; p.interests = []; p.prompts = OnboardingDraft().prompts
        #expect(p.completedStorySections == 0)
        #expect(p.conversationStarters.isEmpty)
        p.bio = "Hello"; p.interests = [.books]; p.prompts[0].answer = "A walk by the lake"
        #expect(p.completedStorySections == 3)
        #expect(p.faith == FaithPreferences())
        #expect(p.conversationStarters.count == 1)
        #expect(p.conversationStarters[0].answer == p.prompts[0].answer)
        #expect(p.conversationStarters[0].draft.contains(p.prompts[0].question))
    }
    @Test func exactAdultBoundaryAndFutureDate() {
        let reference = date(2026, 10, 13)
        #expect(OnboardingDraft.isEligible(birthDate: date(2008, 10, 13), now: reference, calendar: calendar))
        #expect(!OnboardingDraft.isEligible(birthDate: date(2008, 10, 14), now: reference, calendar: calendar))
        #expect(!OnboardingDraft.isEligible(birthDate: date(2027, 1, 1), now: reference, calendar: calendar))
        #expect(OnboardingDraft.age(on: date(2026, 2, 28), birthDate: date(2008, 2, 29), calendar: calendar) == 17)
        #expect(OnboardingDraft.age(on: date(2026, 3, 1), birthDate: date(2008, 2, 29), calendar: calendar) == 18)
    }
    @Test func validatesEveryRequiredOnboardingField() {
        let valid = validDraft()
        for step in 0..<OnboardingDraft.stepCount { #expect(valid.validationError(step: step, now: now) == nil) }
        var d = valid; d.acknowledgedAdult = false; #expect(d.validationError(step: 0) != nil)
        d = valid; d.name = "  "; #expect(d.validationError(step: 0) != nil)
        d = valid; d.birthDate = now; #expect(d.validationError(step: 0, now: now) != nil)
        d = valid; d.gender = nil; #expect(d.validationError(step: 1) != nil)
        d = valid; d.genders = []; #expect(d.validationError(step: 1) != nil)
        d = valid; d.city = " "; #expect(d.validationError(step: 2) != nil)
        d = valid; d.intention = nil; #expect(d.validationError(step: 2) != nil)
        d = valid; d.photos = []; #expect(d.validationError(step: 3) != nil)
    }
    @Test func optionalDetailsCanBeDeferredAndAddedLater() {
        let s = store(); var d = validDraft()
        d.faith = FaithPreferences(); d.interests = []
        d.prompts = OnboardingDraft().prompts
        s.onboarding = d
        #expect(s.completeOnboarding())
        #expect(s.state.currentProfile.interests.isEmpty)
        #expect(s.state.currentProfile.prompts.allSatisfy { $0.answer.isEmpty })
        #expect(s.state.currentProfile.faith.meaning.isEmpty)
        #expect(s.state.currentProfile.faith.sabbath == .shareLater)
        var profile = s.state.currentProfile
        profile.name = "Jordan" // An unrelated edit must not require optional details.
        #expect(s.updateProfile(profile))
        profile.interests = [.books]
        profile.prompts[0].answer = "A walk and a good conversation."
        #expect(s.updateProfile(profile))
        #expect(s.state.currentProfile.interests == [.books])
        let saved = s.state.currentProfile
        profile.prompts[1].answer = "x"
        #expect(!s.updateProfile(profile)); #expect(s.state.currentProfile == saved)
        profile = saved; profile.faith.meaning = String(repeating: "a", count: 301)
        #expect(!s.updateProfile(profile)); #expect(s.state.currentProfile == saved)
    }
    @Test func genderChoicesAndFixturesUseMaleOrFemale() {
        #expect(Set(Gender.allCases.map(\.rawValue)) == ["Male", "Female"])
        #expect(Set(DemoData.people.map(\.gender)) == [.male, .female])
    }
    @Test func onboardingCompletionCommitsProfileAndPreferences() {
        let s = store(); s.onboarding = validDraft(); s.onboarding.radiusMiles = 150
        #expect(s.completeOnboarding())
        #expect(s.hasCompletedOnboarding)
        #expect(s.state.currentProfile.name == "Alex")
        #expect(s.state.discovery.radiusMiles == 150)
        #expect(s.state.discovery.dating.genders == [.female, .male])
        #expect(s.state.currentProfile.age >= 18)
    }
    @Test func completionCannotBypassEligibility() {
        let s = store(); s.onboarding = validDraft(); s.onboarding.birthDate = now
        #expect(!s.completeOnboarding()); #expect(!s.hasCompletedOnboarding); #expect(s.onboardingStep == 0)
    }
    @Test func discoveryFiltersAgeGenderAndSyntheticDistance() {
        let s = store(); #expect(s.discoveryProfiles.count == 3)
        var preferences = s.state.discovery
        preferences.dating.genders = [.female]; preferences.dating.minimumAge = 28; preferences.radiusMiles = 15
        #expect(s.updateDiscovery(preferences))
        #expect(s.discoveryProfiles.map(\.id) == ["amara"])
        preferences.radiusMiles = 250; preferences.dating.genders = [.male]; preferences.dating.minimumAge = 18; preferences.dating.maximumAge = 30
        #expect(s.updateDiscovery(preferences)); #expect(s.discoveryProfiles.map(\.id) == ["rowan"])
    }
    @Test func discoveryIncludesExactAgeAndDistanceBoundaries() {
        let s = store()
        var p = s.state.discovery
        p.dating.minimumAge = 28; p.dating.maximumAge = 28; p.radiusMiles = 12
        #expect(s.updateDiscovery(p)); #expect(s.discoveryProfiles.map(\.id) == ["amara"])
        p.radiusMiles = 11
        #expect(s.updateDiscovery(p)); #expect(s.discoveryProfiles.isEmpty)
        p.radiusMiles = 250; p.dating.minimumAge = 18; p.dating.maximumAge = 100
        #expect(s.updateDiscovery(p)); #expect(s.discoveryProfiles.count == 4)
        p.radiusMiles = 5
        #expect(s.updateDiscovery(p)); #expect(s.discoveryProfiles.isEmpty)
        let saved = s.state.discovery
        for radius in [4, 251] {
            p.radiusMiles = radius
            #expect(!s.updateDiscovery(p)); #expect(s.state.discovery == saved)
        }
    }
    @Test func invalidPreferencesLeavePriorSnapshotIntact() {
        let s = store(); let original = s.state.discovery
        var p = original; p.dating.genders = []
        #expect(!s.updateDiscovery(p)); #expect(s.state.discovery == original)
        p = original; p.dating.minimumAge = 17
        #expect(!s.updateDiscovery(p)); #expect(s.state.discovery == original)
        p = original; p.dating.minimumAge = 60; p.dating.maximumAge = 30
        #expect(!s.updateDiscovery(p)); #expect(s.state.discovery == original)
    }
    @Test func profileAndPromptLikesAreIdempotentAndShareState() {
        let s = store()
        s.like("amara"); s.like("amara")
        s.like("amara", promptID: "amara-0"); s.like("amara", promptID: "amara-0")
        #expect(s.isLiked("amara")); #expect(s.isPromptLiked("amara-0", memberID: "amara"))
        #expect(s.outgoingProfiles.map(\.id) == ["amara"])
        #expect(s.state.likes.filter { $0.senderID == "me" }.count == 2)
        #expect(s.state.matches.filter { $0.memberID == "amara" }.count == 1)
        #expect(s.conversations.filter { $0.memberID == "amara" }.count == 1)
        s.removeLike("amara")
        #expect(!s.isLiked("amara")); #expect(s.outgoingProfiles.isEmpty)
        #expect(s.isMatched("amara")) // Existing chats survive a removed like.
    }
    @Test func nonexistentPromptCannotCreateLike() {
        let s = store(); s.like("amara", promptID: "not-a-prompt")
        #expect(!s.isLiked("amara")); #expect(s.errorMessage != nil)
    }
    @Test func passesAdvanceAndCanBeRevisited() {
        let s = store(); let first = s.discoveryProfiles.first!.id
        s.pass(first); #expect(!s.discoveryProfiles.contains { $0.id == first })
        #expect(s.discoveryProfiles.first?.id != first)
        s.resetPasses(); #expect(s.discoveryProfiles.first?.id == first)
    }
    @Test func undoRestoresOnlyOneSkipAndCannotBypassBlocking() {
        let s = store()
        #expect(s.pass("amara")); #expect(s.pass("eli"))
        #expect(s.undoPass("eli"))
        #expect(s.state.passedIDs == ["amara"])
        #expect(s.discoveryProfiles.contains { $0.id == "eli" })
        s.block("amara")
        #expect(!s.undoPass("amara"))
        #expect(s.member("amara") == nil)
        #expect(s.state.passedIDs == ["amara"])
    }
    @Test func blockingEnforcesAllViewsAndDoesNotRestoreHistory() {
        let s = store(); s.like("amara"); s.block("amara")
        #expect(s.member("amara") == nil); #expect(!s.discoveryProfiles.contains { $0.id == "amara" })
        #expect(!s.incomingProfiles.contains { $0.id == "amara" }); #expect(!s.outgoingProfiles.contains { $0.id == "amara" })
        #expect(!s.isMatched("amara")); #expect(!s.conversations.contains { $0.memberID == "amara" })
        s.like("amara"); #expect(!s.isLiked("amara"))
        s.unblock("amara"); #expect(s.member("amara") != nil)
        #expect(!s.conversations.contains { $0.memberID == "amara" })
        #expect(!s.isLiked("amara"))
    }
    @Test func messageInsertionAndValidation() {
        let s = store(); let before = s.conversations[0].messages.count
        #expect(s.send("  Hello there!  ", conversationID: "chat-eli"))
        #expect(s.conversations[0].messages.count == before + 1)
        #expect(s.conversations[0].messages.last?.text == "Hello there!")
        #expect(s.conversations[0].messages.last?.senderID == "me")
        #expect(s.conversations[0].messages.last?.createdAt == now)
        #expect(!s.send("  \n ", conversationID: "chat-eli"))
        #expect(!s.send(String(repeating: "a", count: 2001), conversationID: "chat-eli"))
        s.markRead("chat-eli"); #expect(s.conversations[0].unreadCount == 0)
        s.block("eli"); #expect(!s.send("hello", conversationID: "chat-eli"))
    }
    @Test func profileEditsAndPublicPrivacyProjection() {
        let s = store(); var profile = s.state.currentProfile
        profile.name = "  Morgan  "; profile.bio = "A new introduction"; profile.interests = [.gardening, .books, .travel]
        #expect(s.updateProfile(profile)); #expect(s.member("me")?.name == "Morgan")
        #expect(s.member("me")?.bio == "A new introduction")
        #expect(s.member("me")?.interests == [.gardening, .books, .travel])
        var privacy = s.state.privacy; privacy.showCity = false; privacy.discoveryPaused = true; s.updatePrivacy(privacy)
        #expect(s.member("me")?.city == "Location private")
        #expect(s.state.currentProfile.city == "Chicago, IL")
        #expect(s.discoveryProfiles.isEmpty)
        privacy.discoveryPaused = false; s.updatePrivacy(privacy); #expect(!s.discoveryProfiles.isEmpty)
    }
    @Test func invalidProfileEditIsAtomic() {
        let s = store(); let before = s.state.currentProfile
        var profile = before; profile.name = ""; profile.city = "New city"
        #expect(!s.updateProfile(profile)); #expect(s.state.currentProfile == before)
    }
    @Test func reportsAreLocalAndSeparateFromBlocking() {
        let s = store(); #expect(s.report("amara", reason: .inappropriate, details: "Sample report"))
        #expect(s.state.reports.count == 1); #expect(s.state.reports.first?.memberID == "amara")
        #expect(s.member("amara") != nil)
        #expect(!s.report("missing", reason: .other, details: ""))
    }
    @Test func notificationPreferencesAreShared() {
        let s = store(); var p = s.state.notifications; p.sabbathQuietMode = true; p.messages = false
        s.updateNotifications(p)
        #expect(s.state.notifications.sabbathQuietMode); #expect(!s.state.notifications.messages)
    }
}

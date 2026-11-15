import Foundation
import Testing
@testable import Kindred

struct KindredPlusTests {
    @Test func entitlementRequiresTheFlagAndAFutureExpiration() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expiration = Date(timeIntervalSince1970: 1_800_000_000)
        let timestamp = expiration.ISO8601Format()
        for (flag, expiresAt, expected) in [(true, "\"\(timestamp)\"", true), (false, "\"\(timestamp)\"", false), (true, "null", false)] {
            let row = Data(#"{"is_plus":\#(flag),"expires_at":\#(expiresAt)}"#.utf8)
            let entitlement = try decoder.decode(PlusEntitlement.self, from: row)
            #expect(entitlement.isActive(at: expiration.addingTimeInterval(-1)) == expected)
            #expect(!entitlement.isActive(at: expiration))
        }
    }

    @Test func likeLimitResponseCarriesTheRemainingCount() {
        let limit = Data(#"{"code":"LIKE_LIMIT_REACHED","message":"Daily like limit reached","details":"{\"remaining\":0,\"resetsAtEpoch\":1800000000}"}"#.utf8)
        let throttle = Data(#"{"code":"PT429","message":"Try again later"}"#.utf8)
        #expect(LikeAllowance.limitReached(in: limit)?.remaining == 0)
        #expect(LikeAllowance.limitReached(in: limit)?.resetsAtEpoch == 1_800_000_000)
        #expect(LikeAllowance.limitReached(in: throttle) == nil)
    }

    @Test func cooldownStartsAtTwelfthLikeAndLastsExactlyTwentyFourHours() throws {
        let formatter = ISO8601DateFormatter()
        let lastLike = try #require(formatter.date(from: "2026-10-31T23:59:00-05:00"))
        let afterMidnight = lastLike.addingTimeInterval(60)
        let reset = lastLike.addingTimeInterval(86_400)
        var allowance = DemoLikeAllowance()
        for _ in 0..<11 { allowance.recordLike(at: lastLike.addingTimeInterval(-86_400)) }
        #expect(allowance.remaining(at: lastLike) == 1)
        #expect(allowance.nextReset(at: lastLike) == nil)
        allowance.recordLike(at: lastLike)
        #expect(allowance.nextReset(at: afterMidnight) == reset)
        #expect(allowance.remaining(at: afterMidnight) == 0)
        allowance.recordLike(at: afterMidnight)
        #expect(allowance.nextReset(at: afterMidnight) == reset)
        #expect(allowance.remaining(at: reset) == 12)
        allowance.recordLike(at: reset)
        #expect(allowance.remaining(at: reset) == 11)
    }

    @MainActor @Test func demoPlusCanHideIncomingIdentitiesWithoutNetwork() throws {
        let store = AppStore()
        let first = try #require(store.pendingIncomingProfiles.first)
        let count = store.pendingIncomingProfiles.count
        store.demoPlusEnabled = false
        #expect(store.pendingIncomingProfiles.isEmpty)
        #expect(store.pendingIncomingCount == count)
        #expect(store.likesRemaining == 12)
        store.demoPlusEnabled = true
        #expect(store.pendingIncomingProfiles.first?.id == first.id)
        #expect(store.likesRemaining == nil)
    }
}

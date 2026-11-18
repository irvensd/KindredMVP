import Foundation

struct PlusEntitlement: Decodable, Sendable {
    let isPlus: Bool
    let expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case isPlus = "is_plus"
        case expiresAt = "expires_at"
    }

    func isActive(at date: Date) -> Bool {
        isPlus && expiresAt.map { $0 > date } == true
    }
}

struct LikeAllowance: Decodable, Sendable {
    static let dailyLimit = 12
    static let cooldown: TimeInterval = 24 * 60 * 60
    let remaining: Int?
    let resetsAtEpoch: TimeInterval?

    static func limitReached(in data: Data) -> Self? {
        struct Failure: Decodable { let code: String; let details: String? }
        guard let failure = try? JSONDecoder().decode(Failure.self, from: data),
              failure.code == "LIKE_LIMIT_REACHED" else { return nil }
        let allowance = failure.details.flatMap { try? JSONDecoder().decode(Self.self, from: Data($0.utf8)) }
        return Self(remaining: 0, resetsAtEpoch: allowance?.resetsAtEpoch)
    }
}

struct DemoLikeAllowance {
    private var used = 0
    private(set) var reset: Date?

    func remaining(at now: Date) -> Int {
        reset.map { $0 <= now } == true ? LikeAllowance.dailyLimit : LikeAllowance.dailyLimit - used
    }

    func nextReset(at now: Date) -> Date? {
        guard let reset, reset > now else { return nil }
        return reset
    }

    mutating func recordLike(at now: Date) {
        let remaining = remaining(at: now)
        guard remaining > 0 else { return }
        used = LikeAllowance.dailyLimit - remaining + 1
        let cooldown: TimeInterval
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        cooldown = arguments.contains("--uitesting") && arguments.contains("--short-free-like-cooldown")
            ? 30 : LikeAllowance.cooldown
        #else
        cooldown = LikeAllowance.cooldown
        #endif
        reset = used == LikeAllowance.dailyLimit ? now.addingTimeInterval(cooldown) : nil
    }
}

import Foundation
import CryptoKit
import Security

struct BackendAccount {
    struct Session: Codable, Sendable {
        let access_token: String
        let user: User
        var refresh_token: String? = nil
        var expires_at: TimeInterval? = nil

        var expiresAt: Date {
            Date(timeIntervalSince1970: expires_at ?? claims?.exp ?? 0)
        }

        var loginID: String { claims?.session_id ?? access_token }

        private var claims: Claims? {
            let segments = access_token.split(separator: ".")
            guard segments.count == 3 else { return nil }
            var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload) else { return nil }
            return try? JSONDecoder().decode(Claims.self, from: data)
        }

        private struct Claims: Decodable {
            let exp: TimeInterval?
            let session_id: String?
        }
    }

    struct User: Codable, Sendable {
        let id: UUID
        let email: String?
    }
    struct Profile: Codable {
        let user_id: UUID
        let display_name: String
    }

    enum RequestError: LocalizedError {
        case rejected(Int)
        var invalidSession: Bool {
            switch self {
            case .rejected(400), .rejected(401), .rejected(403): true
            default: false
            }
        }
        var errorDescription: String? {
            switch self {
            case .rejected(400), .rejected(401): "Check your email and password, or sign in again."
            case .rejected(403): "This profile or conversation is no longer available."
            case .rejected(409): "This report changed. Refresh the queue and try again."
            case .rejected(429): "Too many attempts. Please try again later."
            default: "Kindred couldn’t complete this request. Please try again."
            }
        }
    }

    private static let transport = URLSession(configuration: .ephemeral)
    private let baseURL = URL(string: "https://yogyhusnjlgwkudqtixq.supabase.co")!

    func signIn(email: String, password: String) async throws -> Session {
        let data = try await request("/auth/v1/token?grant_type=password", method: "POST",
                                     body: JSONEncoder().encode(["email": email, "password": password]))
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func refresh(session: Session) async throws -> Session {
        guard let token = session.refresh_token else { throw RequestError.rejected(401) }
        let data = try await request("/auth/v1/token?grant_type=refresh_token", method: "POST",
                                     body: JSONEncoder().encode(["refresh_token": token]))
        let renewed = try JSONDecoder().decode(Session.self, from: data)
        guard renewed.user.id == session.user.id, renewed.loginID == session.loginID,
              renewed.refresh_token != nil else { throw RequestError.rejected(401) }
        return renewed
    }

    static let passwordResetURL = URL(string: "com.kindred.prototype://auth/reset-password")!

    static func isPasswordResetURL(_ url: URL) -> Bool {
        url.scheme == passwordResetURL.scheme && url.host == passwordResetURL.host
            && url.path == passwordResetURL.path && url.port == nil && url.user == nil
    }

    func sendPasswordReset(to email: String) async throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw KindredError.invalid("Couldn’t prepare a secure reset link. Please try again.")
        }
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        try AccountKeychain.save(verifier, for: .passwordRecovery)
        var endpoint = URLComponents()
        endpoint.path = "/auth/v1/recover"
        endpoint.queryItems = [.init(name: "redirect_to", value: Self.passwordResetURL.absoluteString)]
        guard let path = endpoint.string else { throw KindredError.unavailable }
        do {
            _ = try await request(path, method: "POST", body: JSONEncoder().encode([
                "email": email, "code_challenge": challenge, "code_challenge_method": "s256"
            ]))
        } catch RequestError.rejected(400) {
            throw KindredError.invalid("Kindred couldn’t send a reset email. Check the address and try again.")
        }
    }

    func exchangePasswordResetLink(_ url: URL) async throws -> Session {
        guard Self.isPasswordResetURL(url),
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "code" })?.value,
              UUID(uuidString: code) != nil,
              let verifier = try AccountKeychain.load(String.self, for: .passwordRecovery) else {
            throw KindredError.invalid("This reset link can’t be opened here. Request a new link on this device.")
        }
        let data = try await request("/auth/v1/token?grant_type=pkce", method: "POST",
                                     body: JSONEncoder().encode(["auth_code": code, "code_verifier": verifier]))
        let session = try JSONDecoder().decode(Session.self, from: data)
        try? AccountKeychain.remove(.passwordRecovery)
        return session
    }

    func resetPassword(_ password: String, session: Session) async throws {
        _ = try await request("/auth/v1/user", method: "PUT",
                              body: JSONEncoder().encode(["password": password]), session: session)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func signOut(session: Session) async throws {
        do {
            _ = try await request("/auth/v1/logout?scope=local", method: "POST", session: session)
        } catch RequestError.rejected(401), RequestError.rejected(403), RequestError.rejected(404) {
            // Supabase no longer accepts this session.
        }
    }

    func deleteAccount(session: Session, password: String) async throws {
        guard let email = session.user.email, !email.isEmpty else {
            throw KindredError.invalid("Sign in again to confirm which account to delete.")
        }
        let verified = try await signIn(email: email, password: password)
        guard verified.user.id == session.user.id else {
            try? await signOut(session: verified)
            throw KindredError.invalid("This sign-in does not match the account you want to delete.")
        }
        do {
            _ = try await request("/rest/v1/rpc/delete_my_account", method: "POST",
                                  body: Data("{}".utf8), session: verified)
        } catch {
            try? await signOut(session: verified)
            throw error
        }
    }

    func createAccount(email: String, password: String) async throws -> Session? {
        let data = try await request("/auth/v1/signup", method: "POST",
                                     body: JSONEncoder().encode(["email": email, "password": password]))
        struct SignupResponse: Decodable { let access_token: String? }
        let response = try JSONDecoder().decode(SignupResponse.self, from: data)
        guard response.access_token != nil else { return nil }
        return try JSONDecoder().decode(Session.self, from: data)
    }

    func loadProfile(session: Session) async throws -> String {
        let data = try await request("/rest/v1/member_profiles?select=display_name,user_id&user_id=eq.\(session.user.id.uuidString)", session: session)
        return try JSONDecoder().decode([Profile].self, from: data).first?.display_name ?? ""
    }

    func saveProfile(name: String, session: Session) async throws {
        let profile = Profile(user_id: session.user.id, display_name: name)
        _ = try await request("/rest/v1/member_profiles", method: "POST",
                              body: JSONEncoder().encode(profile), session: session)
    }

    struct DiscoveryProfile: Codable, Sendable {
        let user_id: UUID
        var profile: MemberProfile
        var preferences: DiscoveryPreferences
        var privacy: PrivacyPreferences
    }

    func loadDiscoveryProfile(session: Session) async throws -> DiscoveryProfile? {
        let data = try await request("/rest/v1/discovery_profiles?select=user_id,profile,preferences,privacy&user_id=eq.\(session.user.id.uuidString)", session: session)
        return try JSONDecoder().decode([DiscoveryProfile].self, from: data).first
    }

    func saveDiscoveryProfile(_ row: DiscoveryProfile, session: Session) async throws {
        try validateProfileSize(row.profile)
        _ = try await request("/rest/v1/discovery_profiles", method: "POST",
                              body: JSONEncoder().encode(row), session: session)
    }

    struct SettingsChange: Encodable {
        var profile: MemberProfile?
        var preferences: DiscoveryPreferences?
        var privacy: PrivacyPreferences?
    }

    func saveSettings(_ change: SettingsChange, session: Session) async throws {
        if let profile = change.profile { try validateProfileSize(profile) }
        let path = "/rest/v1/discovery_profiles?user_id=eq.\(session.user.id.uuidString)&select=user_id"
        let data = try await request(path, method: "PATCH", body: JSONEncoder().encode(change), session: session)
        struct UpdatedProfile: Decodable { let user_id: UUID }
        guard try JSONDecoder().decode([UpdatedProfile].self, from: data).first?.user_id == session.user.id else {
            throw KindredError.invalid("Your saved profile couldn’t be found. Sign in again and retry.")
        }
    }

    private func validateProfileSize(_ profile: MemberProfile) throws {
        guard try JSONEncoder().encode(profile).count <= 7_900_000 else {
            throw KindredError.invalid("These photos are too large together. Remove a photo and try again.")
        }
    }

    struct DiscoveryPage: Decodable, Sendable {
        struct Cursor: Decodable, Sendable {
            let miles: Int
            let id: UUID
        }

        let profiles: [MemberProfile]
        let next: Cursor?

        private enum CodingKeys: String, CodingKey { case profiles, next }

        init(from decoder: Decoder) throws {
            let page = try decoder.container(keyedBy: CodingKeys.self)
            next = try page.decodeIfPresent(Cursor.self, forKey: .next)
            var rows = try page.nestedUnkeyedContainer(forKey: .profiles)
            var valid: [MemberProfile] = []
            while !rows.isAtEnd {
                let row = try rows.superDecoder()
                guard var profile = try? MemberProfile(from: row) else { continue }
                profile.photos = profile.photos.filter { $0.localData != nil && $0.assetName == nil }
                if !profile.photos.isEmpty { valid.append(profile) }
            }
            profiles = valid
        }
    }

    func discover(after cursor: DiscoveryPage.Cursor?, session: Session) async throws -> DiscoveryPage {
        struct Request: Encodable {
            let after_miles: Int?
            let after_id: UUID?
        }
        let body = try JSONEncoder().encode(Request(after_miles: cursor?.miles, after_id: cursor?.id))
        let data = try await request("/rest/v1/rpc/discovery_page", method: "POST", body: body, session: session)
        return try JSONDecoder().decode(DiscoveryPage.self, from: data)
    }

    struct MessagePage: Decodable, Sendable {
        let messages: [Message]
        let hasMore: Bool
    }

    func conversationHistory(threadID: UUID, before messageID: UUID, session: Session) async throws -> MessagePage {
        let body = try JSONEncoder().encode(["thread_id": threadID, "before_id": messageID])
        let data = try await request("/rest/v1/rpc/conversation_history", method: "POST", body: body, session: session)
        return try timestampDecoder().decode(MessagePage.self, from: data)
    }

    struct MemberBlock: Codable {
        let user_id: UUID
        let blocked_id: UUID
    }

    struct BlockedMemberSummary: Decodable, Sendable {
        let blocked_id: UUID
        let display_name: String?
    }

    func loadBlockedMembers(session: Session) async throws -> [BlockedMemberSummary] {
        let data = try await request("/rest/v1/rpc/blocked_member_summaries", method: "POST",
                                     body: Data("{}".utf8), session: session)
        return try JSONDecoder().decode([BlockedMemberSummary].self, from: data)
    }

    func block(_ id: UUID, session: Session) async throws {
        let body = try JSONEncoder().encode(MemberBlock(user_id: session.user.id, blocked_id: id))
        _ = try await request("/rest/v1/member_blocks", method: "POST", body: body, session: session)
    }

    func unblock(_ id: UUID, session: Session) async throws {
        _ = try await request("/rest/v1/member_blocks?blocked_id=eq.\(id.uuidString)", method: "DELETE", session: session)
    }

    struct Activity: Decodable, Sendable {
        var members: [MemberProfile]
        let likes: [Like]
        let matches: [Match]
        let conversations: [Conversation]
        let endedMemberIDs: Set<String>
        var unseenLikeIDs: Set<String>?
    }

    struct ActivityAction: Encodable, Sendable {
        enum Kind: String, Encodable, Sendable {
            case like, removeLike = "remove_like", unmatch, send, read, report
        }
        let action: Kind
        let target: UUID
        var prompt_id: String?
        var photo_id: String?
        var message_body: String?
        var message_id: UUID?
        var read_message_id: UUID?
        var report_reason: String?
        var report_details: String?
    }

    struct ActivityResult: Decodable, Sendable { let matched: Bool }

    func perform(_ action: ActivityAction, session: Session) async throws -> ActivityResult {
        let data = try await request("/rest/v1/rpc/member_activity_action", method: "POST",
                                     body: JSONEncoder().encode(action), session: session)
        return try JSONDecoder().decode(ActivityResult.self, from: data)
    }

    func loadActivity(session: Session) async throws -> Activity {
        let data = try await request("/rest/v1/rpc/member_activity", method: "POST",
                                     body: Data("{}".utf8), session: session)
        var activity = try timestampDecoder().decode(Activity.self, from: data)
        for index in activity.members.indices {
            activity.members[index].photos.removeAll { $0.localData == nil || $0.assetName != nil }
        }
        return activity
    }

    func markLikesSeen(_ ids: Set<String>, session: Session) async throws {
        let body = try JSONEncoder().encode(["like_ids": ids.sorted()])
        _ = try await request("/rest/v1/rpc/mark_likes_seen", method: "POST", body: body, session: session)
    }

    struct SafetyReport: Decodable, Identifiable, Sendable {
        let id: UUID
        let reason: String
        let details: String
        let created_at: Date
        let reported_id: UUID
        let reported_name: String?
        let assigned_to_me: Bool
        let assigned: Bool
        let reviewed_at: Date?
        let resolution: String?
    }

    enum SafetyAction: String, Encodable, Sendable {
        case claim, release, resolve
    }

    func isSafetyReviewer(session: Session) async throws -> Bool {
        let data = try await request("/rest/v1/rpc/is_safety_reviewer", method: "POST",
                                     body: Data("{}".utf8), session: session)
        return try JSONDecoder().decode(Bool.self, from: data)
    }

    func loadSafetyQueue(reviewed: Bool, offset: Int, session: Session) async throws -> [SafetyReport] {
        struct Query: Encodable { let include_reviewed: Bool; let page_offset: Int }
        let data = try await request("/rest/v1/rpc/safety_report_queue", method: "POST",
                                     body: JSONEncoder().encode(Query(include_reviewed: reviewed, page_offset: offset)),
                                     session: session)
        return try timestampDecoder().decode([SafetyReport].self, from: data)
    }

    func reviewSafetyReport(_ reportID: UUID, action: SafetyAction, note: String? = nil, session: Session) async throws {
        struct Review: Encodable { let report_id: UUID; let action: SafetyAction; let note: String? }
        _ = try await request("/rest/v1/rpc/review_safety_report", method: "POST",
                              body: JSONEncoder().encode(Review(report_id: reportID, action: action, note: note)),
                              session: session)
    }

    private func timestampDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid message date")
        }
        return decoder
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, session: Session? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(BackendProject.publishableKey, forHTTPHeaderField: "apikey")
        if let session { request.setValue("Bearer \(session.access_token)", forHTTPHeaderField: "Authorization") }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if method == "POST" && ["/rest/v1/member_profiles", "/rest/v1/discovery_profiles"].contains(path) { request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer") }
        if method == "POST" && path == "/rest/v1/member_blocks" {
            request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
        }
        if method == "PATCH" { request.setValue("return=representation", forHTTPHeaderField: "Prefer") }
        let (data, response) = try await Self.transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw RequestError.rejected(status) }
        return data
    }
}

import Foundation

struct BackendAccount {
    struct Session: Decodable, Sendable {
        let access_token: String
        let user: User
    }

    struct User: Decodable, Sendable {
        let id: UUID
        let email: String?
    }
    struct Profile: Codable {
        let user_id: UUID
        let display_name: String
    }

    enum RequestError: LocalizedError {
        case rejected(Int)
        var errorDescription: String? {
            switch self {
            case .rejected(400), .rejected(401): "Check your email and password, or sign in again."
            case .rejected(403): "This profile or conversation is no longer available."
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
        struct SignupResponse: Decodable {
            let access_token: String?
            let user: User?
        }
        let data = try await request("/auth/v1/signup", method: "POST",
                                     body: JSONEncoder().encode(["email": email, "password": password]))
        let response = try JSONDecoder().decode(SignupResponse.self, from: data)
        guard let token = response.access_token else { return nil }
        guard let user = response.user else { throw RequestError.rejected(500) }
        return Session(access_token: token, user: user)
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

    func discover(session: Session) async throws -> [MemberProfile] {
        struct Results: Decodable {
            let profiles: [MemberProfile]
            init(from decoder: Decoder) throws {
                var rows = try decoder.unkeyedContainer()
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
        let data = try await request("/rest/v1/rpc/discover_profiles", method: "POST", body: Data("{}".utf8), session: session)
        return try JSONDecoder().decode(Results.self, from: data).profiles
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
        var activity = try decoder.decode(Activity.self, from: data)
        for index in activity.members.indices {
            activity.members[index].photos.removeAll { $0.localData == nil || $0.assetName != nil }
        }
        return activity
    }

    func markLikesSeen(_ ids: Set<String>, session: Session) async throws {
        let body = try JSONEncoder().encode(["like_ids": ids.sorted()])
        _ = try await request("/rest/v1/rpc/mark_likes_seen", method: "POST", body: body, session: session)
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

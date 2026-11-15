import Foundation

enum BackendProject {
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions/")!
    static var url: URL? { url("KindredSupabaseURL") }
    static var publishableKey: String? { value("KindredSupabasePublishableKey") }
    static var revenueCatPublicKey: String? { value("KindredRevenueCatPublicKey") }
    static var privacyPolicyURL: URL? { url("KindredPrivacyPolicyURL", requiresHTTPS: true) }
    static var termsURL: URL {
        url("KindredTermsURL", requiresHTTPS: true)
            ?? URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    }

    private static func value(_ key: String) -> String? {
        guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    private static func url(_ key: String, requiresHTTPS: Bool = false) -> URL? {
        guard let value = value(key), let url = URL(string: value), url.host != nil,
              url.scheme == "https" || (!requiresHTTPS && url.scheme == "http") else { return nil }
        return url
    }
}

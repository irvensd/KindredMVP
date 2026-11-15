import Foundation
import RevenueCat

@MainActor
final class PlusPurchases {
    enum Plan: String, CaseIterable, Identifiable {
        case monthly = "kindred_plus_monthly"
        case threeMonths = "kindred_plus_3month"

        var id: String { rawValue }
        var title: String { self == .monthly ? "Monthly" : "Every 3 months" }
    }

    struct Offer: Identifiable {
        let plan: Plan
        fileprivate let package: Package
        var id: String { plan.id }
        var price: String { package.localizedPriceString }
    }

    private var desiredID: String?
    private var queue: Task<Void, Never>?

    func setAccount(_ userID: UUID?) {
        desiredID = userID?.uuidString.lowercased()
        let expectedID = desiredID
        _ = enqueue {
            guard expectedID == nil || self.desiredID == expectedID else { return }
            try await self.identify(expectedID)
        }
    }

    func offers(for userID: UUID) async throws -> [Offer] {
        try await forAccount(userID) { purchases in
            let packages = try await purchases.offerings().current?.availablePackages ?? []
            return Plan.allCases.compactMap { plan in
                packages.first(where: { $0.storeProduct.productIdentifier == plan.rawValue })
                    .map { Offer(plan: plan, package: $0) }
            }
        }
    }

    func purchase(_ offer: Offer, for userID: UUID) async throws -> Bool {
        try await forAccount(userID) { purchases in
            let result = try await purchases.purchase(package: offer.package)
            return !result.userCancelled
        }
    }

    func restore(for userID: UUID) async throws -> Bool {
        try await forAccount(userID) { purchases in
            try await purchases.restorePurchases().entitlements.active["plus"] != nil
        }
    }

    private func forAccount<T: Sendable>(
        _ userID: UUID, operation: @escaping @MainActor (Purchases) async throws -> T
    ) async throws -> T {
        let expectedID = userID.uuidString.lowercased()
        return try await enqueue {
            guard self.desiredID == expectedID else { throw KindredError.unavailable }
            try await self.identify(expectedID)
            guard self.desiredID == expectedID, Purchases.isConfigured,
                  Purchases.shared.appUserID == expectedID else { throw KindredError.unavailable }
            return try await operation(Purchases.shared)
        }.value
    }

    private func identify(_ id: String?) async throws {
        if let id {
            guard let key = BackendProject.revenueCatPublicKey else { return }
            if !Purchases.isConfigured {
                Purchases.configure(withAPIKey: key, appUserID: id)
            } else if Purchases.shared.appUserID != id {
                _ = try await Purchases.shared.logIn(id)
            }
        } else if Purchases.isConfigured, !Purchases.shared.isAnonymous {
            _ = try await Purchases.shared.logOut()
        }
    }

    // Keep account changes, purchases, and restores ordered across sign-out and account switches.
    private func enqueue<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) -> Task<T, Error> {
        let previous = queue
        let task = Task {
            await previous?.value
            return try await operation()
        }
        queue = Task { _ = await task.result }
        return task
    }
}

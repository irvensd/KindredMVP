import SwiftUI

struct PaywallView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var offers: [PlusPurchases.Offer] = []
    @State private var busy = false
    @State private var checkingActivation = false
    @State private var loading = true
    @State private var planLoadMessage: String?
    @State private var message: String?
    @State private var demoPlan: PlusPurchases.Plan?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeader(eyebrow: "Kindred Plus", title: "See who likes you", subtitle: "Get a closer look at incoming likes and send unlimited likes.")
                    if let reset = store.nextFreeLikeReset {
                        let resetTime = reset.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated)
                            .day().hour().minute().timeZone(.specificName(.short)))
                        NoteCard(symbol: "clock", text: "Free likes refill \(resetTime).")
                            .accessibilityIdentifier("freeLikeReset")
                    }
                    if store.isPlusActivationPending && !store.isPlus {
                        activationStatus
                    } else if store.isDemoSession && store.plusErrorScenario != "plans-offline" {
                        Text("Demo purchase · No charge").font(.footnote.weight(.semibold)).foregroundStyle(Color.plum)
                        if store.demoPlusEnabled {
                            Label("Kindred Plus is active in this demo", systemImage: "checkmark.circle")
                                .font(.headline).foregroundStyle(Color.plum)
                                .accessibilityIdentifier("demoPlusActive")
                            PrimaryButton(title: "Continue exploring") { dismiss() }
                            Button("Return to free demo") { store.demoPlusEnabled = false }
                                .frame(minHeight: 44).accessibilityIdentifier("resetDemoPlus")
                        } else {
                            ForEach(PlusPurchases.Plan.allCases) { plan in
                                PrimaryButton(title: plan.title) { demoPlan = plan }
                                    .accessibilityIdentifier("demoPlan-\(plan.id)")
                            }
                            Text("In the live app, plans renew automatically and can be canceled in App Store settings.")
                                .font(.footnote).foregroundStyle(Color.muted)
                            if store.plusErrorScenario == "empty-restore" { restoreButton }
                        }
                    } else {
                        if store.isPlus {
                            Label("Kindred Plus is active", systemImage: "checkmark.circle")
                                .font(.headline).foregroundStyle(Color.plum)
                        } else if loading {
                            ProgressView("Loading plans…")
                        } else if offers.isEmpty {
                            Text(planLoadMessage ?? "Subscription plans are temporarily unavailable.")
                                .foregroundStyle(Color.muted)
                            Button("Retry loading plans") { Task { await loadOffers() } }
                                .frame(minHeight: 44)
                        } else {
                            ForEach(offers) { offer in
                                PrimaryButton(title: "\(offer.plan.title) · \(offer.price)") {
                                    Task { await activate(offer) }
                                }.disabled(busy)
                            }
                        }
                        Text("Renews automatically at the price shown. Cancel anytime in App Store subscription settings.")
                            .font(.footnote).foregroundStyle(Color.muted)
                        if busy { ProgressView() }
                        restoreButton
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(Color.muted) }
                    HStack(spacing: 20) {
                        Link("Terms of Use", destination: BackendProject.termsURL)
                        if let privacy = BackendProject.privacyPolicyURL {
                            Link("Privacy Policy", destination: privacy)
                        }
                    }.font(.footnote)
                }.padding(24)
            }.background(Color.paper).foregroundStyle(Color.ink)
                .navigationTitle("Kindred Plus").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
        }
        .alert("Simulate subscription?", isPresented: Binding(
            get: { demoPlan != nil },
            set: { if !$0 { demoPlan = nil } }
        ), presenting: demoPlan) { _ in
            Button("Simulate purchase") {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--pending-plus-demo") {
                    store.simulatePendingPlusActivation()
                } else {
                    store.demoPlusEnabled = true
                }
                #else
                store.demoPlusEnabled = true
                #endif
                demoPlan = nil
            }
            Button("Cancel", role: .cancel) { demoPlan = nil }
        } message: { plan in
            Text("\(plan.title). This unlocks Kindred Plus for this demo session. You won’t be charged.")
        }
        .onChange(of: store.isPlus) { _, active in
            if active { message = nil }
        }
        .interactiveDismissDisabled(busy)
        .task { await loadOffers() }
        .task(id: store.isPlusActivationPending) {
            guard store.isPlusActivationPending, !store.isDemoSession else { return }
            for _ in 0..<6 {
                guard !Task.isCancelled, store.isPlusActivationPending else { return }
                if !checkingActivation { await store.checkPlusActivation() }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }

    private var activationStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activating Plus").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("We’re confirming your subscription. You can close this screen and keep using Kindred while it updates.")
                .foregroundStyle(Color.muted)
            PrimaryButton(title: checkingActivation ? "Checking…" : "Check again") {
                guard !checkingActivation else { return }
                checkingActivation = true
                message = nil
                Task {
                    await store.checkPlusActivation()
                    checkingActivation = false
                    if store.isPlusActivationPending {
                        message = store.activityLoadError == nil
                            ? "Still activating. Check again in a moment."
                            : "Couldn’t check your subscription. Try again when you’re connected."
                    }
                }
            }.disabled(checkingActivation)
        }
    }

    private var restoreButton: some View {
        Button("Restore Purchases") { Task { await activate() } }
            .frame(minHeight: 44).disabled(busy || loading)
    }

    private func loadOffers() async {
        let simulateOffline = store.plusErrorScenario == "plans-offline"
        guard (!store.isDemoSession || simulateOffline), !store.isPlusActivationPending else {
            loading = false
            return
        }
        loading = true
        planLoadMessage = nil
        defer { loading = false }
        do {
            if simulateOffline { throw URLError(.notConnectedToInternet) }
            guard BackendProject.privacyPolicyURL != nil else {
                planLoadMessage = "This build needs a Privacy Policy URL before subscriptions can be offered."
                return
            }
            let available = try await store.plusOffers()
            if available.count == PlusPurchases.Plan.allCases.count { offers = available }
        } catch let error as URLError where error.code == .notConnectedToInternet {
            planLoadMessage = "Couldn’t load subscription plans. Check your connection, then try again."
        } catch {
            planLoadMessage = "Couldn’t load subscription plans. Try again in a moment."
        }
    }

    private func activate(_ offer: PlusPurchases.Offer? = nil) async {
        guard !busy, !store.isPlusActivationPending else { return }
        busy = true
        message = nil
        defer { busy = false }
        do { message = try await store.activatePlus(offer: offer) }
        catch { message = error.localizedDescription }
    }
}

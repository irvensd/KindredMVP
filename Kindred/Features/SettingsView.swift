import SwiftUI

struct YouView: View {
    @Environment(AppStore.self) private var store
    @State private var editProfile = false
    @State private var preferences = false
    @State private var showStoryGuide = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(eyebrow: "Beautifully, unapologetically you", title: "Your story", subtitle: "A little care goes a long way.")
                VStack(spacing: 20) {
                    HStack(spacing: 18) {
                        Avatar(profile: store.state.currentProfile, size: 92)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(store.state.currentProfile.name), \(store.state.currentProfile.age)").font(.title2.weight(.semibold))
                            Text(store.state.privacy.showCity ? store.state.currentProfile.city : "Location private").font(.subheadline).foregroundStyle(Color.muted)
                            Text("YOUR LOCAL DEMO PROFILE").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Color.plum)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        Button("Edit profile") { editProfile = true }.buttonStyle(.borderedProminent).foregroundStyle(Color.onPlum).accessibilityIdentifier("editProfile")
                        NavigationLink("Preview") { ProfileDetailView(memberID: "me") }.buttonStyle(.bordered).accessibilityIdentifier("publicPreview").accessibilityHint("Shows your saved profile with your privacy preferences applied.")
                    }.controlSize(.large)
                }.padding(22).frame(maxWidth: .infinity).background(Color.surface, in: RoundedRectangle(cornerRadius: 26))
                if showStoryGuide {
                    let profile = store.state.currentProfile
                    if profile.missingStorySections.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle").font(.headline).foregroundStyle(Color.plum)
                                .accessibilityHidden(true)
                            Text("3 of 3 optional sections added").font(.subheadline).foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("All 3 optional story sections added")
                                .accessibilityIdentifier("storyCompletion")
                            Button { showStoryGuide = false } label: {
                                Image(systemName: "xmark").font(.caption.weight(.semibold))
                                    .frame(width: 44, height: 44).contentShape(Circle())
                            }.buttonStyle(.plain).foregroundStyle(Color.muted)
                                .accessibilityLabel("Hide story summary")
                                .accessibilityIdentifier("hideStoryGuide")
                        }.padding(.vertical, 10).padding(.leading, 18).padding(.trailing, 8)
                            .background(Color.sand, in: RoundedRectangle(cornerRadius: 24))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("completedStorySummary")
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A little more of your story").font(.headline)
                            ProgressView(value: Double(profile.completedStorySections), total: 3) {
                                Text("\(profile.completedStorySections) of 3 optional story sections added").font(.subheadline)
                            }.tint(Color.plum).accessibilityIdentifier("storyCompletion")
                            Text("Make it yours: \(profile.missingStorySections.joined(separator: ", ").lowercased()).")
                                .font(.subheadline).foregroundStyle(Color.muted)
                            Text("Everything here is optional. Faith and lifestyle details are yours to share at your own pace.")
                                .font(.footnote).foregroundStyle(Color.muted)
                            Button("Add a little more") { editProfile = true }
                                .frame(minHeight: 44).accessibilityIdentifier("completeProfile")
                            Button("Hide suggestions") { showStoryGuide = false }.font(.footnote).frame(minHeight: 44)
                                .accessibilityIdentifier("hideStoryGuide")
                        }.padding(22).background(Color.sand, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                VStack(spacing: 0) {
                    Button { preferences = true } label: { SettingsRow(symbol: "slider.horizontal.3", title: "Dating preferences", subtitle: "Ages \(store.state.discovery.dating.minimumAge)–\(store.state.discovery.dating.maximumAge) · \(store.state.discovery.radiusMiles) miles") }.buttonStyle(.plain).accessibilityIdentifier("datingPreferences")
                    Divider().padding(.leading, 56)
                    NavigationLink { NotificationsView() } label: { SettingsRow(symbol: "moon.stars", title: "Notifications & Sabbath", subtitle: store.state.notifications.sabbathQuietMode ? "Sabbath quiet mode on" : "Make space for what matters") }.buttonStyle(.plain)
                    Divider().padding(.leading, 56)
                    NavigationLink { PrivacyView() } label: { SettingsRow(symbol: "lock", title: "Privacy", subtitle: store.state.privacy.discoveryPaused ? "Discovery paused" : "Choose what you share") }.buttonStyle(.plain)
                    Divider().padding(.leading, 56)
                    NavigationLink { SafetyCenterView() } label: { SettingsRow(symbol: "shield.lefthalf.filled", title: "Safety & support", subtitle: "Boundaries are a good thing") }.buttonStyle(.plain)
                    Divider().padding(.leading, 56)
                    NavigationLink { AccountView() } label: { SettingsRow(symbol: "person.crop.circle", title: "Account & prototype", subtitle: "What's real, and what's simulated") }.buttonStyle(.plain)
                }.padding(.horizontal, 18).background(Color.surface, in: RoundedRectangle(cornerRadius: 26))
                HStack(spacing: 8) { BrandMark(size: 18); Text("Shared faith. Genuine connection.").font(.footnote).foregroundStyle(Color.muted) }.frame(maxWidth: .infinity).padding(.top, 12)
                Text("KINDRED · PHASE 1.5 · ALL CHANGES RESET ON RELAUNCH").font(.caption2).tracking(1).foregroundStyle(Color.muted).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }.padding(24)
        }.background(Color.paper).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $editProfile) { EditProfileView(profile: store.state.currentProfile) }
            .sheet(isPresented: $preferences) { DiscoveryPreferencesView() }
    }
}
struct SettingsRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.plum).frame(width: 30)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline).foregroundStyle(Color.ink); Text(subtitle).font(.caption).foregroundStyle(Color.muted) }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.muted)
        }.padding(.vertical, 20).contentShape(Rectangle())
    }
}
struct DiscoveryPreferencesView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = DiscoveryPreferences()
    @State private var validation: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Your kind of connection").font(.title2.weight(.semibold)); Text("These filters immediately shape the fictional profiles in Discover when you save.").foregroundStyle(Color.muted) }
                Section("I'd like to meet") { GenderChoices(selected: $preferences.dating.genders) }
                Section("Age range") {
                    Text("\(preferences.dating.minimumAge)–\(preferences.dating.maximumAge) years")
                        .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Color.plum)
                        .accessibilityIdentifier("ageRangeSummary")
                    Stepper("Minimum age: \(preferences.dating.minimumAge)", value: $preferences.dating.minimumAge, in: 18...preferences.dating.maximumAge)
                        .monospacedDigit().accessibilityIdentifier("minimumAge")
                    Stepper("Maximum age: \(preferences.dating.maximumAge)", value: $preferences.dating.maximumAge, in: preferences.dating.minimumAge...100)
                        .monospacedDigit().accessibilityIdentifier("maximumAge")
                }
                Section { RadiusControl(value: $preferences.radiusMiles, showsPreciseAdjustment: true) } footer: { Text("Distances are fictional sample values. No location permission or precise location is used. Saved preferences stay for this session and reset when the app process relaunches.") }
                Section { Button("Restore default preferences") { preferences = DiscoveryPreferences() } }
            }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle(typeSize.isAccessibilitySize ? "Preferences" : "Discovery preferences").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.updateDiscovery(preferences) { dismiss() } else { validation = store.errorMessage; store.errorMessage = nil } }.fontWeight(.semibold).accessibilityIdentifier("savePreferences") }
                }.onAppear { preferences = store.state.discovery }
                .alert("Check your preferences", isPresented: Binding(get: { validation != nil }, set: { if !$0 { validation = nil } })) { Button("OK") { validation = nil } } message: { Text(validation ?? "") }
        }
    }

}

struct EditProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var profile: MemberProfile
    @State private var validation: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("The essentials") {
                    TextField("First name", text: $profile.name).textContentType(.givenName).accessibilityIdentifier("editName")
                    TextField("City or general area", text: $profile.city)
                    TextField("What fills your days?", text: $profile.occupation)
                    TextField("Your bio (up to 500 characters)", text: $profile.bio, axis: .vertical).lineLimit(3...6)
                    Picker("Gender", selection: $profile.gender) { ForEach(Gender.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("I'm looking for", selection: $profile.intention) { ForEach(Intention.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section { Text("Only save what feels like you. Optional sections can stay blank; Cancel keeps your saved profile unchanged.").font(.footnote).foregroundStyle(Color.muted) }
                Section("Your interests · optional") { InterestPicker(selected: $profile.interests) }
                Section("Faith & lifestyle · optional") { FaithEditor(faith: $profile.faith) }
                Section("Your voice · optional") { PromptEditor(prompts: $profile.prompts) }
                Section("Your photos") { PhotoEditor(photos: $profile.photos) }
                Section { Text("Your age is set during onboarding. Changes to date of birth will require verified account support in a production app.").font(.footnote).foregroundStyle(Color.muted) }
            }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Edit your story").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.updateProfile(profile) { dismiss() } else { validation = store.errorMessage; store.errorMessage = nil } }.fontWeight(.semibold).accessibilityIdentifier("saveProfile") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissKeyboard() } }
                }
                .alert("Check your story", isPresented: Binding(get: { validation != nil }, set: { if !$0 { validation = nil } })) { Button("OK") { validation = nil } } message: { Text(validation ?? "") }
        }
    }
}
struct PrivacyView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Form {
            Section {
                Toggle("Show my city on my profile", isOn: Binding(get: { store.state.privacy.showCity }, set: { var p = store.state.privacy; p.showCity = $0; store.updatePrivacy(p) }))
                Toggle("Pause discovery", isOn: Binding(get: { store.state.privacy.discoveryPaused }, set: { var p = store.state.privacy; p.discoveryPaused = $0; store.updatePrivacy(p) }))
            } footer: { Text("Hiding your city changes your public profile preview. Pausing discovery stops profile browsing in this demo. In production, server-side rules must also hide you from other members.") }
            Section("Your private space") {
                Label("No precise location collected", systemImage: "location.slash")
                Label("No analytics or tracking", systemImage: "eye.slash")
                Label("No photos or messages uploaded", systemImage: "lock")
                Text("Everything, including your onboarding answers and imported photos, stays in memory for this session. Closing the app's process clears it. This is a prototype privacy boundary, not a production security guarantee.").font(.footnote).foregroundStyle(Color.muted)
            }
        }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Privacy")
    }
}
struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @State private var preview: String?
    var body: some View {
        Form {
            Section {
                Toggle("Like previews", isOn: preference(\.likes))
                Toggle("Message previews", isOn: preference(\.messages))
                Toggle("Sabbath quiet mode", isOn: preference(\.sabbathQuietMode))
            } footer: { Text("Preferences control the in-app previews below. Push notifications are unavailable. Sabbath scheduling will use a chosen timezone and sunset policy in Phase 2.") }
            Section("Try your preferences") {
                Button("Preview a like alert") { preview = store.state.notifications.likes ? "Sample alert: someone liked your profile." : "Like alerts are off. Nothing would be shown." }
                Button("Preview a message alert") { preview = store.state.notifications.messages ? "Sample alert: a new conversation is waiting." : "Message alerts are off. Nothing would be shown." }
                Button("Preview a Sabbath message alert") {
                    preview = store.state.notifications.sabbathQuietMode ? "Quiet mode: this sample alert is silenced during Sabbath." : store.state.notifications.messages ? "Quiet mode is off: a sample message alert would appear." : "Message alerts are off. Nothing would be shown."
                }
                if let preview { Text(preview).font(.subheadline).foregroundStyle(Color.plum).accessibilityIdentifier("notificationPreview") }
            }
            Section { Text("No operating-system notification permissions are requested, no notifications are scheduled, and no one else is contacted.").font(.footnote).foregroundStyle(Color.muted) }
        }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("A little quiet")
    }
    private func preference(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { store.state.notifications[keyPath: keyPath] }, set: { value in var p = store.state.notifications; p[keyPath: keyPath] = value; store.updateNotifications(p) })
    }
}
struct SafetyCenterView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section("Your comfort comes first") {
                Text("Take your time. Keep early conversations in-app, protect private details, and choose a public place for a first meeting. You never owe anyone a conversation.").font(.body)
                Text("Profiles here are fictional and unverified. Demo reports are not sent to or reviewed by anyone.").font(.footnote).foregroundStyle(Color.muted)
            }
            Section("Blocked profiles") {
                if store.state.blocks.isEmpty { Text("No blocked profiles").foregroundStyle(Color.muted) }
                ForEach(store.state.blocks) { block in
                    HStack { Text(store.state.members.first { $0.id == block.memberID }?.name ?? "Profile"); Spacer(); Button("Unblock") { store.unblock(block.memberID) } }
                }
            }
            Section("Local reports") {
                Text("\(store.state.reports.count) report(s) saved in this session").foregroundStyle(Color.muted)
                Text("Use the safety menu on any profile or conversation to report or block. Unblocking never restores removed chats or likes.").font(.footnote).foregroundStyle(Color.muted)
            }
        }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Safety & support")
    }
}
struct AccountView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section("A transparent prototype") {
                Text("Kindred · Phase 1.5").font(.headline)
                Text("No real account exists. All profiles, matches, incoming likes and conversations are fictional. All data resets when the app process relaunches.")
            }
            Section("Unavailable in this prototype") {
                Label("Authentication & account verification", systemImage: "person.badge.key")
                Label("Live matching & message delivery", systemImage: "network")
                Label("Push notifications", systemImage: "bell")
                Label("Data export & account deletion", systemImage: "externaldrive")
                Text("These require a production backend, authorization, consent and retention policies. There are no payments or subscriptions.").font(.footnote).foregroundStyle(Color.muted)
            }
            Section {
                Button("Return to welcome") { store.hasCompletedOnboarding = false; store.isOnboarding = false }
            } footer: { Text("This keeps the current in-memory session. Terminate and relaunch the app for a fresh demo.") }
        }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("About your account")
    }
}

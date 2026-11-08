import SwiftUI

struct YouView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppStore.self) private var store
    @State private var editProfile = false
    @State private var preferences = false
    @State private var showStoryGuide = true
    private enum SheetAction: Hashable { case edit, complete, preferences }
    @State private var editingAction = SheetAction.edit
    @AccessibilityFocusState private var focusedAction: SheetAction?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(eyebrow: "Beautifully, unapologetically you", title: "Your story", subtitle: "A little care goes a long way.")
                VStack(spacing: 20) {
                    let identityLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))
                    identityLayout {
                        Avatar(profile: store.state.currentProfile, size: 92)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(store.state.currentProfile.name), \(store.state.currentProfile.age)").font(.title2.weight(.semibold))
                            Text(store.state.privacy.showCity ? store.state.currentProfile.city : "Location private").font(.subheadline).foregroundStyle(Color.muted)
                            if store.isDemoSession { Text("YOUR LOCAL DEMO PROFILE").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Color.plum) }
                        }
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    let editLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                    editLayout {
                        Button("Edit profile") { editingAction = .edit; editProfile = true }.buttonStyle(.borderedProminent).foregroundStyle(Color.onPlum).accessibilityIdentifier("editProfile").accessibilityFocused($focusedAction, equals: .edit)
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
                            }.buttonStyle(KindredPressStyle()).foregroundStyle(Color.muted)
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
                            Button("Add a little more") { editingAction = .complete; editProfile = true }
                                .frame(minHeight: 44).accessibilityIdentifier("completeProfile").accessibilityFocused($focusedAction, equals: .complete)
                            Button("Hide suggestions") { showStoryGuide = false }.font(.footnote).frame(minHeight: 44)
                                .accessibilityIdentifier("hideStoryGuide")
                        }.padding(22).background(Color.sand, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
                VStack(spacing: 0) {
                    Button { preferences = true } label: { SettingsRow(symbol: "slider.horizontal.3", title: "Dating preferences", subtitle: "Ages \(store.state.discovery.dating.minimumAge)–\(store.state.discovery.dating.maximumAge) · \(store.state.discovery.radiusMiles) miles") }.buttonStyle(KindredPressStyle()).accessibilityIdentifier("datingPreferences").accessibilityFocused($focusedAction, equals: .preferences)
                    Divider().padding(.leading, 56)
                    if store.isDemoSession {
                        NavigationLink { NotificationsView() } label: { SettingsRow(symbol: "moon.stars", title: "Notifications & Sabbath", subtitle: store.state.notifications.sabbathQuietMode ? "Sabbath quiet mode on" : "Make space for what matters") }.buttonStyle(KindredPressStyle())
                        Divider().padding(.leading, 56)
                    }
                    NavigationLink { PrivacyView() } label: { SettingsRow(symbol: "lock", title: "Privacy", subtitle: store.state.privacy.discoveryPaused ? "Discovery paused" : "Choose what you share") }.buttonStyle(KindredPressStyle())
                    Divider().padding(.leading, 56)
                    NavigationLink { SafetyCenterView() } label: { SettingsRow(symbol: "shield.lefthalf.filled", title: "Safety & support", subtitle: "Boundaries are a good thing") }.buttonStyle(KindredPressStyle())
                    Divider().padding(.leading, 56)
                    NavigationLink { AccountView() } label: { SettingsRow(symbol: "person.crop.circle", title: store.isDemoSession ? "Account & prototype" : "Account", subtitle: store.isDemoSession ? "What's real, and what's simulated" : "Your Kindred account") }.buttonStyle(KindredPressStyle())
                }.padding(.horizontal, 18).background(Color.surface, in: RoundedRectangle(cornerRadius: 26))
                HStack(spacing: 8) { BrandMark(size: 18); Text("Shared faith. Genuine connection.").font(.footnote).foregroundStyle(Color.muted) }.frame(maxWidth: .infinity).padding(.top, 12)
                if store.isDemoSession {
                    Text("KINDRED · PHASE 1.5 · ALL CHANGES RESET ON RELAUNCH")
                        .font(.caption2).tracking(1).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
            }.padding(24)
        }.background(Color.paper).scrollEdgeEffectStyle(.hard, for: .bottom).modifier(StatusAreaProtection()).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $editProfile, onDismiss: { focusedAction = editingAction }) { EditProfileView(profile: store.state.currentProfile) }
            .sheet(isPresented: $preferences, onDismiss: { focusedAction = .preferences }) { DiscoveryPreferencesView() }
    }
}
struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: symbol).foregroundStyle(Color.plum)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.muted)
                    }.font(.body).accessibilityHidden(true)
                    Text(title).font(.headline).foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.caption).foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 16) {
                    Image(systemName: symbol).font(.title3).foregroundStyle(Color.plum).frame(width: 30)
                    VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline).foregroundStyle(Color.ink); Text(subtitle).font(.caption).foregroundStyle(Color.muted) }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.muted)
                }
            }
        }.padding(.vertical, 20).contentShape(Rectangle())
    }
}
struct DiscoveryPreferencesView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = DiscoveryPreferences()
    @State private var validation: String?
    @State private var confirmDiscard = false
    @State private var didSave = false
    @State private var saving = false
    private var hasChanges: Bool { preferences != store.state.discovery }
    var body: some View {
        NavigationStack {
            Form {
                if typeSize.isAccessibilitySize {
                    Text("Preferences")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Section { Text("Your kind of connection").font(.title2.weight(.semibold)); Text(store.isDemoSession ? "These filters immediately shape the fictional profiles in Discover when you save." : "Choose who you’d like to meet and how far you’d like to search.").foregroundStyle(Color.muted) }
                Section {
                    Text("Home city: \(store.state.currentProfile.city)").foregroundStyle(Color.muted)
                    if !store.isDemoSession {
                        Toggle("Search near my home city", isOn: $preferences.useHomeCityForSearch)
                    }
                    if !preferences.useHomeCityForSearch {
                        Picker("Search near", selection: $preferences.searchCity) {
                            ForEach(SearchCity.allCases) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("searchCity")
                    }
                    if store.isDemoSession, let home = SearchCity.matching(store.state.currentProfile.city), home != preferences.searchCity {
                        Button("Search near my home city") { preferences.searchCity = home }
                    }
                } header: { Text("Where you'd like to meet") }
                  footer: { Text(store.isDemoSession ? "Your home city is self-reported and stays on your profile. Search near is private. This offline demo supports the cities listed here." : "Your home city appears on your profile. Your search city is private.") }
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
                Section { RadiusControl(value: $preferences.radiusMiles, showsPreciseAdjustment: true) } footer: { Text(store.isDemoSession ? "Distances are approximate miles between the selected search city and each fictional member’s home city center. They do not track travel status. Saved preferences stay for this session and reset when the app process relaunches." : "Distances are approximate. For cities outside the supported search list, Discover can match members who entered the same city.") }
                Section {
                    Button("Restore default preferences") {
                        preferences = store.isDemoSession ? DiscoveryPreferences() : .defaults(forHomeCity: store.state.currentProfile.city)
                    }
                }
            }.disabled(saving).interactiveDismissDisabled(saving).scrollContentBackground(.hidden).background(Color.paper).navigationTitle(typeSize.isAccessibilitySize ? "" : "Preferences").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") {
                            guard !didSave, !saving else { return }
                            if store.isDemoSession {
                                finishSaving(store.updateDiscovery(preferences))
                            } else {
                                saving = true
                                Task {
                                    finishSaving(await store.saveDiscoveryChanges(preferences))
                                    saving = false
                                }
                            }
                        }.fontWeight(.semibold).accessibilityIdentifier("savePreferences").disabled(didSave || saving)
                    }
                }.onAppear { preferences = store.state.discovery }
                .background(SheetDismissalGuard(hasChanges: hasChanges) { confirmDiscard = true })
                .alert("Discard changes?", isPresented: $confirmDiscard) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) { }
                } message: { Text("Your unsaved changes will be lost.") }
                .alert("Check your preferences", isPresented: Binding(get: { validation != nil }, set: { if !$0 { validation = nil } })) { Button("OK") { validation = nil } } message: { Text(validation ?? "") }
        }
    }

    private func finishSaving(_ success: Bool) {
        if success { didSave = true; dismiss() }
        else { validation = store.errorMessage; store.errorMessage = nil }
    }
}

struct EditProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var profile: MemberProfile
    @State private var keyboardVisible = false
    @State private var validation: String?
    @State private var attemptedSave = false
    private var issues: [ProfileValidationIssue] { attemptedSave ? profile.validationIssues : [] }
    private func error(_ field: String) -> String? { issues.first { $0.id == field }?.message }
    @State private var confirmDiscard = false
    @State private var didSave = false
    @State private var saving = false
    private var hasChanges: Bool { profile != store.state.currentProfile }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section("The essentials") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("First name", text: $profile.name).textContentType(.givenName).accessibilityIdentifier("editName")
                        ProfileFieldError(message: error("name"), field: "name")
                    }.id("name")
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Home city or general area", text: $profile.city).accessibilityIdentifier("editCity")
                        ProfileFieldError(message: error("city"), field: "city")
                    }.id("city")
                    TextField("What fills your days?", text: $profile.occupation)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Your bio (up to 500 characters)", text: $profile.bio, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("editBio")
                        ProfileFieldError(message: error("bio"), field: "bio")
                    }.id("bio")
                    Picker("Gender", selection: $profile.gender) { ForEach(Gender.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("I'm looking for", selection: $profile.intention) { ForEach(Intention.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section {
                    ForEach(DistanceOpenness.allCases) { choice in
                        Button { profile.distanceOpenness = choice } label: {
                            HStack(spacing: 12) {
                                Text(choice.rawValue)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: profile.distanceOpenness == choice ? "checkmark.circle.fill" : "circle")
                                    .accessibilityHidden(true)
                            }.foregroundStyle(profile.distanceOpenness == choice ? Color.plum : Color.ink)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(KindredPressStyle())
                            .accessibilityLabel(choice.rawValue)
                            .accessibilityAddTraits(profile.distanceOpenness == choice ? .isSelected : [])
                    }
                    Toggle("Open to relocating", isOn: $profile.openToRelocating)
                        .accessibilityIdentifier("openToRelocating")
                } header: { Text("Distance & relocation · optional") }
                  footer: { Text("Shared choices appear on your profile. Relocation is shown only when enabled. Set your search city and radius separately in Discovery preferences.") }
                Section {
                    Picker("Travel status", selection: $profile.locationStatus) {
                        ForEach(LocationStatus.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("locationStatus")
                    if profile.locationStatus != .home {
                        Picker("Destination", selection: $profile.destination) {
                            ForEach(SearchCity.allCases) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("travelDestination")
                    }
                } header: { Text("Visiting or moving · optional") }
                  footer: { Text(store.isDemoSession
                    ? "Home city and travel plans are self-reported. Changing these does not change your Search near city. Hide your city in Privacy to hide both from your preview."
                    : "If you search near home, changing your home city also changes where you search. Hide your city in Privacy to hide both your city and travel plans from your profile.") }
                Section { Text("Only save what feels like you. Optional sections can stay blank; Cancel keeps your saved profile unchanged.").font(.footnote).foregroundStyle(Color.muted) }
                Section("What you enjoy · optional") { InterestPicker(selected: $profile.interests); ProfileFieldError(message: error("interests"), field: "interests") }.id("interests")
                Section("Faith & lifestyle · optional") { FaithEditor(faith: $profile.faith, validationMessage: error("faith")) }
                Section("Your voice · optional") { ProfileFieldError(message: error("prompts"), field: "prompts"); PromptEditor(prompts: $profile.prompts, issues: issues) }.id("prompts")
                Section("Your photos") { ProfileFieldError(message: error("photos"), field: "photos"); PhotoEditor(photos: $profile.photos, showsDemoPortraits: store.isDemoSession) }.id("photos")
                Section { ProfileFieldError(message: error("age"), field: "age"); Text("Your age is set during onboarding. Changes to date of birth will require verified account support in a production app.").font(.footnote).foregroundStyle(Color.muted) }.id("age")
            }.disabled(saving).interactiveDismissDisabled(saving).scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Edit your story").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard !didSave, !saving else { return }
                        attemptedSave = true
                        if let first = profile.validationIssues.first {
                            dismissKeyboard()
                            DispatchQueue.main.async {
                                proxy.scrollTo(first.id, anchor: .top)
                                UIAccessibility.post(notification: .announcement, argument: first.message)
                            }
                        } else if store.isDemoSession {
                            finishSaving(store.updateProfile(profile))
                        } else {
                            dismissKeyboard()
                            saving = true
                            Task {
                                finishSaving(await store.saveProfileChanges(profile))
                                saving = false
                            }
                        }
                    }.fontWeight(.semibold).accessibilityIdentifier("saveProfile").disabled(didSave || saving) }
                    if keyboardVisible { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismissKeyboard() } } }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
                .background(SheetDismissalGuard(hasChanges: hasChanges) { confirmDiscard = true })
                .alert("Discard changes?", isPresented: $confirmDiscard) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) { }
                } message: { Text("Your unsaved changes will be lost.") }
                .alert("Check your story", isPresented: Binding(get: { validation != nil }, set: { if !$0 { validation = nil } })) { Button("OK") { validation = nil } } message: { Text(validation ?? "") }
            }
        }
    }
    private func finishSaving(_ success: Bool) {
        if success { didSave = true; dismiss() }
        else { validation = store.errorMessage; store.errorMessage = nil }
    }
}
struct PrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var saving = false
    @State private var saveError: String?
    var body: some View {
        Form {
            Section {
                Toggle("Show my city on my profile", isOn: Binding(get: { store.state.privacy.showCity }, set: { var p = store.state.privacy; p.showCity = $0; savePrivacy(p) })).disabled(saving)
                Toggle("Pause discovery", isOn: Binding(get: { store.state.privacy.discoveryPaused }, set: { var p = store.state.privacy; p.discoveryPaused = $0; savePrivacy(p) })).disabled(saving)
            } footer: { Text(store.isDemoSession ? "Hiding your city changes your public profile preview. Pausing discovery stops profile browsing in this demo." : "Hiding your city removes it from your shared profile. Pausing discovery hides you from other members in Discover.") }
            if saving { ProgressView("Saving privacy settings…") }
            if let saveError { Text(saveError).foregroundStyle(Color.plum) }
            Section("Your private space") {
                Label("No precise location collected", systemImage: "location.slash")
                Label("No analytics or tracking", systemImage: "eye.slash")
                if store.isDemoSession {
                    Label("No photos or messages uploaded", systemImage: "lock")
                    Text("Demo data stays in memory for this session.").font(.footnote).foregroundStyle(Color.muted)
                } else {
                    Text("Your saved profile and photos can be viewed by eligible members and your connections. Your email and birthday do not appear in Discover.").font(.footnote).foregroundStyle(Color.muted)
                }
            }
        }.scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Privacy")
    }

    private func savePrivacy(_ privacy: PrivacyPreferences) {
        guard !saving else { return }
        if store.isDemoSession { store.updatePrivacy(privacy); return }
        saving = true
        saveError = nil
        Task {
            if !(await store.savePrivacyChanges(privacy)) {
                saveError = store.errorMessage ?? "Your privacy settings couldn’t be saved. Please try again."
                store.errorMessage = nil
            }
            saving = false
        }
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
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var unblocking: Set<String> = []
    var body: some View {
        List {
            Section("Your comfort comes first") {
                Text("Take your time. Keep early conversations in-app, protect private details, and choose a public place for a first meeting. You never owe anyone a conversation.").font(.body)
                if store.isDemoSession {
                    Text("Profiles here are fictional and unverified. Demo reports are not sent to or reviewed by anyone.").font(.footnote).foregroundStyle(Color.muted)
                }
            }
            Section {
                if !store.isDemoSession && (loading || !hasLoaded) && !loadFailed {
                    ProgressView("Loading blocked profiles…")
                } else if loadFailed {
                    Text("Couldn’t load blocked profiles.").foregroundStyle(Color.muted)
                    Button("Try again") { Task { await loadBlocks() } }
                } else if store.state.blocks.isEmpty {
                    Text("No blocked profiles").foregroundStyle(Color.muted)
                }
                ForEach(store.state.blocks) { block in
                    let name = block.displayName ?? store.state.members.first { $0.id == block.memberID }?.name ?? "Unavailable profile"
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.headline)
                        Button(unblocking.contains(block.memberID) ? "Unblocking…" : "Unblock") {
                            if store.isDemoSession { store.unblock(block.memberID) }
                            else if unblocking.insert(block.memberID).inserted {
                                Task {
                                    defer { unblocking.remove(block.memberID) }
                                    await store.unblockAccountMember(block.memberID)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .disabled(unblocking.contains(block.memberID))
                        .accessibilityLabel("Unblock \(name)")
                    }
                }
            } header: {
                Text("Blocked profiles")
            } footer: {
                if !store.isDemoSession { Text("Unblocking someone does not restore an ended chat or match.") }
            }
            if store.isDemoSession {
                Section("Local reports") {
                    Text("\(store.state.reports.count) report(s) saved in this session").foregroundStyle(Color.muted)
                    Text("Use the safety menu on any profile or conversation to report or block. Unblocking never restores removed chats or likes.").font(.footnote).foregroundStyle(Color.muted)
                }
            }
        }.task { await loadBlocks() }
            .scrollContentBackground(.hidden).background(Color.paper).navigationTitle("Safety & support")
    }
    private func loadBlocks() async {
        guard !store.isDemoSession, !loading else { return }
        loading = true
        loadFailed = false
        let success = await store.refreshAccountBlocks()
        hasLoaded = success
        loadFailed = !success && !Task.isCancelled
        loading = false
    }
}
struct AccountView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmingSignOut = false
    @State private var signingOut = false
    @State private var signOutError: String?
    @State private var showingDeleteAccount = false

    var body: some View {
        Group {
            if store.isDemoSession { demoAccount }
            else { memberAccount }
        }
        .navigationTitle(store.isDemoSession ? "About your account" : "Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of Kindred?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                signingOut = true
                Task {
                    defer { signingOut = false }
                    do { try await store.signOutAccount() }
                    catch { signOutError = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile and messages stay saved. You can sign in again anytime.")
        }
        .alert("Couldn’t sign out", isPresented: Binding(get: { signOutError != nil }, set: { if !$0 { signOutError = nil } })) {
            Button("OK", role: .cancel) { signOutError = nil }
        } message: {
            Text(signOutError ?? "")
        }
        .sheet(isPresented: $showingDeleteAccount) { DeleteAccountView() }
    }

    private var memberAccount: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    BrandMark(size: 30).accessibilityHidden(true)
                    Overline(text: "Signed in")
                    Text(store.state.currentProfile.name)
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let email = store.accountEmail {
                        Text(email).font(.subheadline).foregroundStyle(Color.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(Color.plum.opacity(0.10), in: RoundedRectangle(cornerRadius: 26))

                Button {
                    confirmingSignOut = true
                } label: {
                    Label(signingOut ? "Signing out…" : "Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(KindredPressStyle())
                .foregroundStyle(Color.plum)
                .background(Color.surface, in: Capsule())
                .disabled(signingOut)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Account deletion").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Permanently remove your profile, photos, likes, matches, and chats.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    Button("Delete account", systemImage: "trash", role: .destructive) {
                        showingDeleteAccount = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(signingOut)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
            }
            .foregroundStyle(Color.ink)
            .padding(24)
        }
        .background(Color.paper.ignoresSafeArea())
    }

    private var demoAccount: some View {
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
                Button("Return to welcome") { store.returnToWelcome() }
            }
        }.scrollContentBackground(.hidden).background(Color.paper)
    }
}

private struct DeleteAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var deleting = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Delete your Kindred account?")
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Your account, profile, and conversations will be permanently removed. This can’t be undone.")
                        .foregroundStyle(Color.muted)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm your password").font(.headline)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(16)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.plum)
                    }
                    Button(deleting ? "Deleting…" : "Permanently delete account", role: .destructive) {
                        deleting = true
                        failure = nil
                        let confirmation = password
                        Task {
                            defer { deleting = false; password = "" }
                            do { try await store.deleteAccount(password: confirmation) }
                            catch { failure = error.localizedDescription }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(password.isEmpty || deleting)
                }
                .foregroundStyle(Color.ink)
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(deleting)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(deleting)
                }
            }
            .interactiveDismissDisabled(deleting)
        }
    }
}

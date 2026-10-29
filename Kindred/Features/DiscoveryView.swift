import SwiftUI

struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.kindredReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showPreferences = false
    @State private var selectedID: String?
    @State private var lastPassedID: String?
    @State private var transitionDirection: CGFloat = 1
    private var current: MemberProfile? { store.discoveryProfiles.first { $0.id == selectedID } ?? store.discoveryProfiles.first }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Color.clear.frame(height: 0).id("discoveryTop").accessibilityHidden(true)
                HStack(alignment: .top) {
                    PageHeader(eyebrow: "A connection worth finding", title: "For you", subtitle: "Shared values. A spark that's your own.")
                    if !typeSize.isAccessibilitySize { BrandMark(size: 29).padding(.top, 25) }
                }
                Button { showPreferences = true } label: {
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Discovery preferences").font(.headline)
                                Text("Within \(store.state.discovery.radiusMiles) miles")
                                Text("Ages \(store.state.discovery.dating.minimumAge)–\(store.state.discovery.dating.maximumAge)")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Within \(store.state.discovery.radiusMiles) miles")
                                Text("·")
                                Text("Ages \(store.state.discovery.dating.minimumAge)–\(store.state.discovery.dating.maximumAge)")
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                    }.font(.caption.weight(.medium)).foregroundStyle(Color.muted).padding(.vertical, 13).padding(.horizontal, 15).background(Color.sand.opacity(0.7), in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(.plain).accessibilityLabel("Discovery preferences").accessibilityIdentifier("discoveryPreferences")
                if let profile = current {
                    VStack(alignment: .leading, spacing: 18) {
                        DiscoveryPortrait(profile: profile, isLiked: store.isLiked(profile.id), next: skip, interested: { store.like(profile.id) })
                            .id(profile.id)
                        ViewThatFits(in: .horizontal) {
                            HStack {
                            Label("Seventh-day Adventist", systemImage: "leaf").font(.footnote.weight(.medium)).foregroundStyle(Color.plum)
                            Spacer()
                            Text("\(profile.distanceMiles) mi · sample").font(.caption).foregroundStyle(Color.muted)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Seventh-day Adventist").font(.footnote).foregroundStyle(Color.plum)
                                Text("\(profile.distanceMiles) mi · sample").font(.caption).foregroundStyle(Color.muted)
                            }
                        }
                        Text(profile.bio).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        InterestChips(interests: profile.interests)
                        NavigationLink { ProfileDetailView(memberID: profile.id) } label: {
                            HStack { Text("Meet \(profile.name)").font(.headline); Spacer(); Image(systemName: "arrow.up.right") }.padding(.vertical, 12)
                        }.accessibilityIdentifier("openProfile")
                        if let prompt = profile.prompts.first(where: { !$0.answer.trimmed.isEmpty }) { PromptCard(prompt: prompt, memberID: profile.id) }

                    }.id(profile.id)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: transitionDirection * 20)))
                } else {
                    switch store.discoveryEmptyReason {
                    case .paused:
                        EmptyState(symbol: "pause.circle", title: "A little breathing room", message: "Discovery is paused. Resume whenever you're ready.")
                        PrimaryButton(title: "Resume discovery") { var privacy = store.state.privacy; privacy.discoveryPaused = false; store.updatePrivacy(privacy) }
                    case .filters:
                        EmptyState(symbol: "slider.horizontal.3", title: "No profiles match your preferences", message: "None of the available fictional members fit your current age, gender and distance preferences. Adjust your filters to explore this demo circle.")
                        PrimaryButton(title: "Adjust preferences") { showPreferences = true }
                    case .seenEveryone:
                        EmptyState(symbol: "checkmark.circle", title: "You've seen everyone for now", message: "You've passed every available profile that fits your preferences. Revisit them or adjust your filters to explore further.")
                        PrimaryButton(title: "Revisit passed profiles") { store.resetPasses(); lastPassedID = nil }
                        Button("Adjust preferences") { showPreferences = true }.frame(maxWidth: .infinity, minHeight: 44)
                    case .unavailable, nil:
                        EmptyState(symbol: "sparkles", title: "No profiles available", message: "There are no available members in this demo session. Changing your filters or revisiting passed profiles won't restore blocked members.")
                    }
                }
                NoteCard(symbol: "sparkles", text: "A thoughtfully simulated experience. All people and incoming activity are fictional; portraits are AI-generated.")
            }.padding(24)
        }.background(Color.paper).scrollEdgeEffectStyle(.hard, for: .bottom).modifier(StatusAreaProtection()).toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if current != nil || undoName != nil {
                    DiscoveryActionBar(name: current?.name, isLiked: current.map { store.isLiked($0.id) } ?? false, undoName: undoName,
                                       next: skip, interested: { if let id = current?.id { store.like(id) } }, undo: undoSkip)
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                }
            }
            .onChange(of: current?.id) { _, _ in proxy.scrollTo("discoveryTop", anchor: .top) }
            .onChange(of: store.state.discovery) { _, _ in lastPassedID = nil }
            .onChange(of: store.state.privacy.discoveryPaused) { _, _ in lastPassedID = nil }
            .sheet(isPresented: $showPreferences) { DiscoveryPreferencesView() }
        }
    }
    private var undoName: String? {
        guard let id = lastPassedID, store.state.passedIDs.contains(id) else { return nil }
        return store.member(id)?.name
    }
    private func skip() {
        guard let id = current?.id else { return }
        transitionDirection = 1
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            if store.pass(id) {
                lastPassedID = id; selectedID = nil; store.feedback = nil
                UIAccessibility.post(notification: .announcement, argument: current.map { "Next introduction, \($0.name)" } ?? "No more introductions. You can undo your last skip.")
            }
        }
    }
    private func undoSkip() {
        guard let id = lastPassedID else { return }
        transitionDirection = -1
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            if store.undoPass(id) {
                selectedID = id; lastPassedID = nil; store.feedback = nil
                UIAccessibility.post(notification: .announcement, argument: "Introduction restored")
            }
        }
    }
}

/// Reachable actions stay separate from the vertically scrolling profile.
private struct DiscoveryActionBar: View {
    @Environment(\.kindredReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var interestSymbolWidth: CGFloat = 20
    let name: String?
    let isLiked: Bool
    let undoName: String?
    let next: () -> Void
    let interested: () -> Void
    let undo: () -> Void

    var body: some View {
        Group {
            if let name {
                ViewThatFits(in: .horizontal) {
                    if !typeSize.isAccessibilitySize {
                        HStack(spacing: 8) {
                            nextButton(name: name, compact: true)
                            interestButton(name: name, compact: true)
                            undoSlot(compact: true)
                        }.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            nextButton(name: name, compact: false)
                            undoSlot(compact: true)
                        }
                        interestButton(name: name, compact: false)
                    }
                }
            } else if let undoName {
                undoButton(name: undoName, compact: false)
            }
        }.frame(maxWidth: .infinity).padding(8)
            .glassEffect(.regular.tint(Color.paper.opacity(0.65)), in: RoundedRectangle(cornerRadius: 30))
    }

    private func nextButton(name: String, compact: Bool) -> some View {
        Button(action: next) {
            HStack(spacing: 8) {
                Text("Next")
                Image(systemName: "arrow.right").font(.subheadline.weight(.medium))
            }.font(.headline)
                .frame(minWidth: compact ? 84 : 0, maxWidth: compact ? nil : .infinity, minHeight: 54)
                .contentShape(Capsule())
        }.buttonStyle(DiscoveryPressStyle()).foregroundStyle(Color.ink)
            .accessibilityLabel("Next introduction, skip \(name)")
            .accessibilityHint("You can undo this skip.").accessibilityIdentifier("passProfile")
    }

    private func interestButton(name: String, compact: Bool) -> some View {
        Button(action: interested) {
            ZStack {
                // Reserve the unsaved label's size so saving interest cannot move Next.
                interestLabel(saved: false).hidden().accessibilityHidden(true)
                interestLabel(saved: isLiked)
            }.font(.headline).fixedSize(horizontal: compact, vertical: true)
                .padding(.horizontal, 16).frame(maxWidth: compact ? nil : .infinity, minHeight: 54)
                .foregroundStyle(Color.onPlum).background(Color.plum, in: Capsule()).contentShape(Capsule())
        }.buttonStyle(DiscoveryPressStyle()).disabled(isLiked)
            .accessibilityLabel(isLiked ? "Interest saved for \(name)" : "I'm interested in \(name)")
            .accessibilityHint(isLiked ? "Saved in your Likes tab." : "Saves a like in this demo. Does not send a message.")
            .accessibilityIdentifier("likeProfile")
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isLiked)
    }

    private func interestLabel(saved: Bool) -> some View {
        HStack(spacing: 9) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: saved ? "checkmark" : "sparkles")
                    .frame(width: interestSymbolWidth)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            Text(saved ? "Interested" : "I'm interested")
        }
    }

    private func undoSlot(compact: Bool) -> some View {
        // Keep the slot's geometry even when there is no skip to undo. The
        // invisible placeholder is neither interactive nor exposed to VoiceOver.
        Group {
            if compact {
                Color.clear.frame(width: 44, height: 44)
            } else {
                Label("Undo skip", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44).hidden()
            }
        }.accessibilityHidden(true)
            .overlay {
                if let undoName { undoButton(name: undoName, compact: compact) }
            }
    }

    private func undoButton(name: String, compact: Bool) -> some View {
        Button(action: undo) {
            Group {
                if compact { Image(systemName: "arrow.uturn.backward") }
                else { Label("Undo skip", systemImage: "arrow.uturn.backward") }
            }.font(.subheadline.weight(.medium))
                .frame(width: compact ? 44 : nil)
                .frame(maxWidth: compact ? nil : .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(DiscoveryPressStyle()).foregroundStyle(Color.plum)
            .accessibilityLabel("Undo skip of \(name)")
            .accessibilityHint("Restores the last introduction you skipped.")
            .accessibilityIdentifier("undoPass")
    }
}

private struct DiscoveryPressStyle: ButtonStyle {
    @Environment(\.kindredReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: configuration.isPressed)
    }
}

struct PromptCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.kindredReduceMotion) private var reduceMotion
    let prompt: ProfilePrompt
    let memberID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.question).font(.subheadline.weight(.medium)).foregroundStyle(Color.plum).accessibilityAddTraits(.isHeader)
            Text(prompt.answer).font(.title3.weight(.medium)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if memberID != "me" {
                HStack {
                    Spacer()
                    Button { store.like(memberID, promptID: prompt.id) } label: {
                        Label(store.isPromptLiked(prompt.id, memberID: memberID) ? "Answer saved" : "Like this answer", systemImage: store.isPromptLiked(prompt.id, memberID: memberID) ? "checkmark" : "sparkles")
                            .font(.caption.weight(.semibold)).padding(.horizontal, 15).frame(minHeight: 44).background(Color.surface, in: Capsule())
                    }.buttonStyle(InterestSaveButtonStyle()).foregroundStyle(Color.plum)
                        .disabled(store.isPromptLiked(prompt.id, memberID: memberID))
                        .accessibilityIdentifier("promptLike-\(memberID)-\(prompt.id)")
                        .accessibilityHint("Saves interest in this person's answer. No message is sent.")
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isPromptLiked(prompt.id, memberID: memberID))
                        .accessibilityLabel("\(store.isPromptLiked(prompt.id, memberID: memberID) ? "Saved" : "Like") answer to \(prompt.question)")
                        .accessibilityValue("\(store.member(memberID)?.name ?? "This person")’s answer")
                }
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color.sand, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct ProfileDetailView: View {
    @Environment(AppStore.self) private var store
    let memberID: String
    var body: some View {
        Group {
            if let profile = store.member(memberID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        PhotoGallery(profile: profile)
                        if memberID == "me" { Overline(text: "Your public profile preview") }
                        VStack(alignment: .leading, spacing: 12) {
                            Overline(text: "A little about me")
                            Text(profile.bio).font(.title3).lineSpacing(5)
                        }
                        Label(profile.intention.rawValue, systemImage: "heart.text.clipboard").font(.headline).foregroundStyle(Color.plum)
                        InterestChips(interests: profile.interests)
                        if let first = profile.prompts.first(where: { !$0.answer.trimmed.isEmpty }) { PromptCard(prompt: first, memberID: memberID) }
                        VStack(alignment: .leading, spacing: 18) {
                            Overline(text: "Faith in everyday life")
                            Text(profile.faith.meaning.isEmpty ? "A conversation to share in time." : profile.faith.meaning).font(.body).lineSpacing(4)
                            Divider()
                            Label(profile.faith.sabbath.rawValue, systemImage: "sun.horizon").font(.subheadline)
                            Label(profile.faith.food.rawValue, systemImage: "leaf").font(.subheadline)
                            Text("Seventh-day Adventist · Shared values, never a score").font(.caption).foregroundStyle(Color.muted)
                        }.padding(24).background(Color.surface, in: RoundedRectangle(cornerRadius: 24))
                        if profile.photos.count > 1 {
                            VStack(alignment: .leading, spacing: 8) {
                                PhotoView(photo: profile.photos[1]).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 24))
                                Text(profile.photos[1].caption).font(.caption).foregroundStyle(Color.muted)
                                if memberID != "me" {
                                    HStack { Spacer(minLength: 0); PhotoInterestButton(profile: profile, photo: profile.photos[1], location: "story") }
                                }
                            }
                        }
                        ForEach(profile.prompts.filter { !$0.answer.trimmed.isEmpty }.dropFirst()) { PromptCard(prompt: $0, memberID: memberID) }
                        if memberID != "me" {
                            PrimaryButton(title: store.isLiked(memberID) ? "Interest saved" : "I'm interested", symbol: store.isLiked(memberID) ? "checkmark" : "sparkles") { store.like(memberID) }.disabled(store.isLiked(memberID)).accessibilityIdentifier("detailLike")
                            NoteCard(symbol: "shield", text: "Trust your pace. Report or block anytime from the safety menu above. Reports are only saved locally in this prototype.")
                        }
                    }.padding(24)
                }
            } else {
                EmptyState(symbol: "hand.raised", title: "Profile unavailable", message: "This profile has been blocked. You can manage blocked profiles in You → Safety.")
            }
        }.background(Color.paper).navigationTitle(memberID == "me" ? "Your story" : store.member(memberID)?.name ?? "Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar { if memberID != "me", store.member(memberID) != nil { ToolbarItem(placement: .topBarTrailing) { SafetyMenu(memberID: memberID) } } }
    }
}
struct SafetyMenu: View {
    @Environment(AppStore.self) private var store
    let memberID: String
    @State private var report = false
    @State private var confirmBlock = false
    @State private var unmatchID: String?
    var body: some View {
        Menu {
            if store.isMatched(memberID) {
                Button("Unmatch", systemImage: "person.crop.circle.badge.minus", role: .destructive) { unmatchID = memberID }
            }
            Button("Report profile", systemImage: "flag") { report = true }
            Button("Block profile", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Profile safety options")
            .modifier(UnmatchConfirmation(memberID: $unmatchID))
            .sheet(isPresented: $report) { ReportView(memberID: memberID) }
            .confirmationDialog("Block \(store.member(memberID)?.name ?? "this profile")?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block profile", role: .destructive) { store.block(memberID) }
            } message: { Text("Their profile, likes, and conversations will be removed from this demo session. Unblocking won't restore old messages.") }
    }
}
struct ReportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let memberID: String
    @State private var reason = ReportReason.inappropriate
    @State private var details = ""
    @State private var saved = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Your comfort matters.").font(.title2.weight(.semibold)); Text("This report is stored only in memory. It is not sent to a moderation team or reviewed.").foregroundStyle(Color.muted) }
                Section("What happened?") {
                    Picker("Reason", selection: $reason) { ForEach(ReportReason.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Optional details (up to 1,000 characters)", text: $details, axis: .vertical).lineLimit(4...8)
                }
                Button("Save demo report") { saved = store.report(memberID, reason: reason, details: details) }.disabled(details.count > 1000)
            }.navigationTitle("Report profile").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .alert("Saved on this device", isPresented: $saved) { Button("Done") { dismiss() } } message: { Text("No report was transmitted. For immediate safety, you can also block this demo profile.") }
        }
    }
}

struct UnmatchConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var memberID: String?
    func body(content: Content) -> some View {
        content.alert("Unmatch with \(memberID.flatMap { store.member($0)?.name } ?? "this person")?", isPresented: Binding(get: { memberID != nil }, set: { if !$0 { memberID = nil } })) {
            Button("Unmatch", role: .destructive) {
                if let id = memberID { store.unmatch(id) }
                memberID = nil
            }
            Button("Keep connection", role: .cancel) { memberID = nil }
        } message: {
            Text("This removes your connection, both sides’ saved interest, and this chat, including messages and your draft, from this demo session. It cannot be undone in this session. This does not block the person; their profile may still appear in Discover.")
        }
    }
}

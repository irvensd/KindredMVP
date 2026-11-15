import SwiftUI

struct LikesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isActive: Bool
    @State private var isVisible = false
    @State private var showingIncoming = true
    @State private var unmatchID: String?
    private var profiles: [MemberProfile] {
        if !showingIncoming { return store.outgoingProfiles }
        let candidates = store.isDemoSession ? store.incomingProfiles : store.state.matches.compactMap { store.member($0.memberID) }
        return candidates.filter { store.isMatched($0.id) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "A little possibility", title: "Good feelings", subtitle: "Sometimes, the feeling is mutual.")
                #if DEBUG
                if store.isDemoSession && ProcessInfo.processInfo.arguments.contains("--test-plus-expiration") {
                    Button("Simulate Plus expiration") { store.demoPlusEnabled = false }
                }
                #endif
                if let error = store.activityLoadError {
                    NoteCard(symbol: "wifi.exclamationmark", text: error)
                    Button("Refresh likes") { Task { await store.refreshActivity() } }
                }
                Picker("Likes", selection: $showingIncoming) {
                    Text("Liked you").tag(true)
                    Text("Your likes").tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("likesSegment")
                if profiles.isEmpty && !showingIncoming {
                    EmptyState(symbol: "heart", title: "Someone will catch your eye", message: "A photo, an answer, a little shared feeling. Save what catches your eye in Discover.")
                } else {
                    ForEach([true, false], id: \.self) { matched in
                        let members = profiles.filter { store.isMatched($0.id) == matched }
                        if !members.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(matched ? "Mutual connections" : "Interest sent")
                                    .font(.headline).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
                                Text(matched ? "You both felt a connection. Start with hello." : "A little interest, with room to grow.")
                                    .font(.subheadline).foregroundStyle(Color.muted)
                            }
                    ForEach(members) { profile in
                        VStack(alignment: .leading, spacing: 0) {
                            NavigationLink { ProfileDetailView(memberID: profile.id) } label: {
                                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(spacing: 18))) {
                                    PhotoView(photo: profile.photos.first).frame(width: 110, height: 145).clipShape(RoundedRectangle(cornerRadius: 20))
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("\(profile.name), \(profile.age)").font(.title2.weight(.semibold)).foregroundStyle(Color.ink)
                                        Text(profile.city).font(.subheadline).foregroundStyle(Color.muted)
                                        Text(store.isMatched(profile.id) ? "Mutual interest" : "Awaiting mutual interest")
                                            .font(.caption.weight(.semibold)).foregroundStyle(Color.plum)
                                        Image(systemName: "arrow.up.right").foregroundStyle(Color.plum)
                                    }.fixedSize(horizontal: false, vertical: true)
                                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                                }
                            }.buttonStyle(KindredPressStyle())
                            if !showingIncoming {
                                ForEach(store.savedInterests(for: profile.id)) { detail in
                                    NavigationLink {
                                        ProfileDetailView(memberID: profile.id, savedTarget: detail.target)
                                    } label: {
                                        HStack {
                                            SavedInterestDetail(detail: detail)
                                            Image(systemName: "chevron.right")
                                                .font(.caption).foregroundStyle(Color.muted)
                                                .accessibilityHidden(true)
                                        }.frame(minHeight: 44).contentShape(Rectangle())
                                    }
                                    .buttonStyle(KindredPressStyle())
                                    .accessibilityHint(detail.photo == nil ? "Opens this answer in the profile" : "Opens this photo in the profile")
                                    .padding(.top, 18)
                                }
                            }
                            Divider().padding(.vertical, 18)
                            if store.isMatched(profile.id) && dynamicTypeSize.isAccessibilitySize {
                                unmatchButton(profile)
                                    .padding(.bottom, 12)
                            }
                            if let conversation = store.conversations.first(where: { $0.memberID == profile.id }) {
                                NavigationLink { ConversationView(conversationID: conversation.id) } label: {
                                    Label("Say hello", systemImage: "bubble.left")
                                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.borderedProminent).tint(Color.plum).foregroundStyle(Color.onPlum)
                                    .accessibilityLabel("Say hello to \(profile.name)")
                                    .accessibilityIdentifier("sayHello-\(profile.id)")
                            }
                            if !showingIncoming {
                                Button("Remove interest") { store.removeLike(profile.id) }
                                    .font(.footnote).foregroundStyle(Color.muted).buttonStyle(KindredPressStyle())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityLabel("Remove interest for \(profile.name)")
                                    .accessibilityIdentifier("removeLike-\(profile.id)")
                                    .padding(.top, store.isMatched(profile.id) ? 8 : 0)
                                Text(store.isMatched(profile.id) ? "Removes your saved interest, including photo and answer likes. Your connection and chat stay." : "Removes your saved interest in this person.")
                                    .font(.caption).foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if store.isMatched(profile.id) && !dynamicTypeSize.isAccessibilitySize {
                                unmatchButton(profile)
                            }
                        }.padding(18).background(Color.surface, in: RoundedRectangle(cornerRadius: 26))
                    }
                        }
                    }
                }
                if showingIncoming { IncomingLikesSection() }
                if store.isDemoSession { NoteCard(symbol: "sparkles", text: showingIncoming ? "Demo likes · Liking back opens a local chat. No notifications are sent." : "Demo likes reset on relaunch. Removing interest keeps your connection and chat.") }
            }.padding(24)
        }.modifier(UnmatchConfirmation(memberID: $unmatchID))
            .refreshable {
                await store.refreshActivity()
                if showingIncoming { await store.refreshIncomingLikes() }
            }
            .task(id: isActive && showingIncoming) {
                if isActive && showingIncoming { await store.refreshIncomingLikes() }
            }
            .onChange(of: store.isPlus) { _, _ in
                if isActive && showingIncoming { Task { await store.refreshIncomingLikes() } }
            }
            .onAppear { isVisible = true; markIncomingIfVisible() }
            .onDisappear { isVisible = false }
            .onChange(of: isActive) { _, _ in markIncomingIfVisible() }
            .onChange(of: showingIncoming) { _, _ in markIncomingIfVisible() }
            .onChange(of: store.incomingActivityCount) { _, _ in
                if isActive && showingIncoming { Task { await store.refreshIncomingLikes() } }
            }
            .onChange(of: store.unseenLikesCount) { _, _ in markIncomingIfVisible() }
            .background(Color.paper).scrollEdgeEffectStyle(.hard, for: .bottom).modifier(StatusAreaProtection()).toolbar(.hidden, for: .navigationBar)
    }
    private func unmatchButton(_ profile: MemberProfile) -> some View {
        Button(role: .destructive) { unmatchID = profile.id } label: {
            Text("Unmatch").font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Unmatch with \(profile.name)")
        .accessibilityIdentifier("unmatch-\(profile.id)")
    }

    private func markIncomingIfVisible() {
        guard isVisible, isActive, showingIncoming else { return }
        Task { await store.markIncomingLikesSeen() }
    }
}


private struct IncomingLikesSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14), count: textSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = store.incomingLikesError {
                Text(error).foregroundStyle(Color.muted)
                Button("Refresh incoming likes") { Task { await store.refreshIncomingLikes() } }
            } else if let count = store.pendingIncomingCount {
                if count > 0 {
                    Text(count == 1 ? "1 person likes you" : "\(count) people like you")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    if store.isPlus {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.pendingIncomingProfiles) { profile in
                                card(profile)
                            }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(0..<min(count, 4), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 20).fill(Color.sand).frame(height: 128)
                                    .overlay {
                                        Image(systemName: "person.fill").font(.largeTitle)
                                            .accessibilityHidden(true)
                                            .foregroundStyle(Color.plum.opacity(0.55)).blur(radius: 9)
                                    }
                            }
                        }.accessibilityHidden(true)
                        PrimaryButton(title: "See who likes you", symbol: textSize.isAccessibilitySize ? nil : "heart") {
                            store.isShowingPlus = true
                        }
                    }
                } else {
                    Text("You haven’t received any new likes yet.").foregroundStyle(Color.muted)
                }
            } else {
                ProgressView("Loading incoming likes…")
            }
        }
    }

    private func card(_ profile: MemberProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { ProfileDetailView(memberID: profile.id) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    PhotoView(photo: profile.photos.first).frame(height: 135)
                        .clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
                    Text("\(profile.name), \(profile.age)").font(.headline).foregroundStyle(Color.ink)
                }
            }.buttonStyle(KindredPressStyle())
            Button("Like back") { store.like(profile.id) }
                .buttonStyle(.borderedProminent).tint(Color.plum)
                .accessibilityLabel("Like back \(profile.name)")
            Button("Pass") { Task { await store.passIncomingLike(profile.id) } }
                .frame(minHeight: 44).accessibilityLabel("Pass on \(profile.name)")
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(Color.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

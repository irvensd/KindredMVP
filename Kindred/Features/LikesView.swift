import SwiftUI

struct LikesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isActive: Bool
    @State private var isVisible = false
    @State private var showingIncoming = true
    @State private var unmatchID: String?
    private var profiles: [MemberProfile] { showingIncoming ? store.incomingProfiles : store.outgoingProfiles }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "A little possibility", title: "Good feelings", subtitle: "Sometimes, the feeling is mutual.")
                if let error = store.activityLoadError {
                    NoteCard(symbol: "wifi.exclamationmark", text: error)
                    Button("Refresh likes") { Task { await store.refreshActivity() } }
                }
                Picker("Likes", selection: $showingIncoming) {
                    Text("Liked you").tag(true)
                    Text("Your likes").tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("likesSegment")
                if profiles.isEmpty {
                    EmptyState(symbol: "heart", title: showingIncoming ? "Room for a new spark" : "Someone will catch your eye", message: showingIncoming ? (store.isDemoSession ? "There are no incoming sample likes in this session." : "You haven’t received any likes yet.") : "A photo, an answer, a little shared feeling. Save what catches your eye in Discover.")
                } else {
                    ForEach([true, false], id: \.self) { matched in
                        let members = profiles.filter { store.isMatched($0.id) == matched }
                        if !members.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(matched ? "Mutual connections" : showingIncoming ? "Waiting for your interest" : "Interest sent")
                                    .font(.headline).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
                                Text(matched ? "You both felt a connection. Start with hello." : showingIncoming ? "Someone noticed you. Take a closer look." : "A little interest, with room to grow.")
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
                                        Text(store.isMatched(profile.id) ? "Mutual interest" : showingIncoming ? "Liked you" : "Awaiting mutual interest")
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
                            if store.isMatched(profile.id) {
                                NavigationLink { ConversationView(conversationID: "chat-\(profile.id)") } label: {
                                    Label("Say hello", systemImage: "bubble.left")
                                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.borderedProminent).tint(Color.plum).foregroundStyle(Color.onPlum)
                                    .accessibilityLabel("Say hello to \(profile.name)")
                                    .accessibilityIdentifier("sayHello-\(profile.id)")
                            } else if showingIncoming {
                                Button { store.like(profile.id) } label: {
                                    Label("Like back", systemImage: "heart").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                }.accessibilityLabel("Like back \(profile.name)")
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
                            if store.isMatched(profile.id) {
                                Button("Unmatch", role: .destructive) { unmatchID = profile.id }
                                    .font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityLabel("Unmatch with \(profile.name)")
                                    .accessibilityIdentifier("unmatch-\(profile.id)")
                            }
                        }.padding(18).background(Color.surface, in: RoundedRectangle(cornerRadius: 26))
                    }
                        }
                    }
                }
                if store.isDemoSession { NoteCard(symbol: "sparkles", text: showingIncoming ? "Demo likes · Liking back opens a local chat. No notifications are sent." : "Demo likes reset on relaunch. Removing interest keeps your connection and chat.") }
            }.padding(24)
        }.modifier(UnmatchConfirmation(memberID: $unmatchID))
            .refreshable { await store.refreshActivity() }
            .onAppear { isVisible = true; markIncomingIfVisible() }
            .onDisappear { isVisible = false }
            .onChange(of: isActive) { _, _ in markIncomingIfVisible() }
            .onChange(of: showingIncoming) { _, _ in markIncomingIfVisible() }
            .onChange(of: store.unseenLikeIDs) { _, _ in markIncomingIfVisible() }
            .background(Color.paper).scrollEdgeEffectStyle(.hard, for: .bottom).modifier(StatusAreaProtection()).toolbar(.hidden, for: .navigationBar)
    }
    private func markIncomingIfVisible() {
        guard isVisible, isActive, showingIncoming else { return }
        Task { await store.markIncomingLikesSeen() }
    }
}

import SwiftUI

struct ChatsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var unreadOnly = false
    @FocusState private var searching: Bool
    private var visibleConversations: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.conversations.filter { conversation in
            (!unreadOnly || conversation.unreadCount > 0) &&
            (query.isEmpty || store.member(conversation.memberID)?.name.localizedStandardContains(query) == true)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Let the conversation unfold", title: "Say hello", subtitle: "Big connections start with small words.")
                NoteCard(symbol: "bubble.left.and.text.bubble.right", text: "Demo chats · Messages stay in this session and are never delivered.")
                if !store.conversations.isEmpty {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Color.muted).accessibilityHidden(true)
                            TextField("Search by name", text: $search)
                                .focused($searching).submitLabel(.search)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                                .accessibilityIdentifier("conversationSearch")
                                .onSubmit { searching = false }
                            if !search.isEmpty {
                                Button { search = "" } label: {
                                    Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                                }.foregroundStyle(Color.muted).accessibilityLabel("Clear name search")
                            }
                        }.padding(.horizontal, 14).frame(minHeight: 52)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
                        Picker("Conversations", selection: $unreadOnly) {
                            Text("All").tag(false)
                            Text("Unread").tag(true)
                        }.pickerStyle(.segmented).accessibilityIdentifier("conversationFilter")
                    }
                }
                if store.conversations.isEmpty {
                    EmptyState(symbol: "bubble.left", title: "Your next hello is waiting", message: "Like back from Likes to start a local chat.")
                } else if visibleConversations.isEmpty {
                    EmptyState(
                        symbol: unreadOnly ? "envelope.open" : "magnifyingglass",
                        title: search.trimmed.isEmpty ? "You're all caught up" : "No conversations found",
                        message: search.trimmed.isEmpty ? "Your conversations will appear here when there are unread messages." : "Try another name or view all conversations."
                    )
                    Button("Show all conversations") { search = ""; unreadOnly = false; searching = false }
                        .frame(minHeight: 44)
                } else {
                    VStack(spacing: 0) {
                        ForEach(visibleConversations) { conversation in
                            if let profile = store.member(conversation.memberID) {
                                NavigationLink(value: conversation.id) {
                                    HStack(alignment: .top, spacing: 16) {
                                        Avatar(profile: profile, size: 70)
                                        VStack(alignment: .leading, spacing: 8) {
                                            if typeSize.isAccessibilitySize {
                                                Text(profile.name).font(.headline).foregroundStyle(Color.ink)
                                                if let date = conversation.messages.last?.createdAt {
                                                    Text(previewDate(date)).font(.caption).foregroundStyle(Color.muted)
                                                }
                                            } else {
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Text(profile.name).font(.headline).foregroundStyle(Color.ink)
                                                Spacer()
                                                if let date = conversation.messages.last?.createdAt { Text(previewDate(date)).font(.caption).foregroundStyle(Color.muted).fixedSize() }
                                            }
                                            }
                                            Text(conversation.preview).font(.subheadline).foregroundStyle(Color.muted).lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(.leading)
                                        }
                                        if conversation.unreadCount > 0 {
                                            Text("\(conversation.unreadCount)").font(.caption2.bold()).foregroundStyle(Color.onPlum).padding(7).background(Color.plum, in: Circle()).accessibilityLabel("\(conversation.unreadCount) unread sample messages")
                                        }
                                    }.padding(.vertical, 18)
                                }.buttonStyle(KindredPressStyle()).accessibilityIdentifier("conversation-\(conversation.memberID)")
                                if conversation.id != visibleConversations.last?.id {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                }
                }
                VStack(spacing: 10) {
                    Image(systemName: "leaf").font(.title2).foregroundStyle(Color.plum)
                    Text("Be curious. Be kind. Be yourself.").font(.subheadline).foregroundStyle(Color.muted)
                }.frame(maxWidth: .infinity).padding(.top, 30)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively)
            .onDisappear { searching = false }
            .background(Color.paper).scrollEdgeEffectStyle(.hard, for: .bottom).modifier(StatusAreaProtection()).toolbar(.hidden, for: .navigationBar)
    }
    private func previewDate(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .omitted)
    }
}
struct ConversationView: View {
    @Environment(AppStore.self) private var store
    let conversationID: String
    private var draft: String {
        get { store.draft(for: conversationID) }
        nonmutating set { store.updateDraft(newValue, conversationID: conversationID) }
    }
    @FocusState private var composing: Bool
    @State private var showStarters = false
    @State private var pendingStarter: String?
    @Environment(\.kindredReduceMotion) private var reduceMotion
    private var conversation: Conversation? { store.conversations.first { $0.id == conversationID } }
    var body: some View {
        Group {
            if let conversation, let profile = store.member(conversation.memberID) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            VStack(spacing: 10) {
                                Avatar(profile: profile, size: 80)
                                Text("A little hello to \(profile.name)").font(.title3.weight(.semibold))
                                NavigationLink("View profile") { ProfileDetailView(memberID: profile.id) }.font(.subheadline).frame(minHeight: 44)
                            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                            if conversation.messages.isEmpty {
                                Text("Your conversation starts here").font(.headline).accessibilityAddTraits(.isHeader)
                                Text("A thoughtful question is enough. This demo won't generate replies.").font(.subheadline).foregroundStyle(Color.muted)
                            }
                            if !profile.conversationStarters.isEmpty && showStarters {
                                starterIdeas(profile).id("starterIdeas")
                            }
                            ForEach(conversation.days()) { day in
                                Text(day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                                    .font(.caption.weight(.medium)).foregroundStyle(Color.muted)
                                    .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("messageDay")
                                ForEach(day.messages) { message in
                                    MessageBubble(message: message, memberName: profile.name).id(message.id)
                                }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(20)
                    }.scrollDismissesKeyboard(.interactively)
                        .defaultScrollAnchor(.bottom)
                        .defaultScrollAnchor(.top, for: .alignment)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                            if composing { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onChange(of: conversation.messages.count) { _, _ in
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onChange(of: showStarters) { _, shown in
                            if shown { composing = false; proxy.scrollTo("starterIdeas", anchor: .top) }
                        }
                        .onChange(of: composing) { _, focused in
                            if focused { showStarters = false; proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onAppear { store.markRead(conversationID); showStarters = conversation.messages.isEmpty && draft.isEmpty }
                        .onDisappear { composing = false }
                }.safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if !profile.conversationStarters.isEmpty && !composing {
                            Button(showStarters ? "Hide conversation ideas" : "Conversation ideas") { showStarters.toggle() }
                                .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                                .accessibilityHint("Optional questions based on their profile. Choosing one fills a draft.")
                                .accessibilityIdentifier("conversationIdeas")
                        }
                        HStack(alignment: .bottom, spacing: 10) {
                            TextField("Write a message…", text: Binding(get: { draft }, set: { draft = $0 }), axis: .vertical).lineLimit(1...5).focused($composing)
                                .padding(.horizontal, 16).padding(.vertical, 13).background(Color.surface, in: RoundedRectangle(cornerRadius: 24)).accessibilityIdentifier("messageComposer")
                            Button {
                                if store.send(draft, conversationID: conversationID) { draft = ""; showStarters = false }
                            } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 48, height: 48).foregroundStyle(Color.onPlum).background(Color.plum, in: Circle()) }
                                .buttonStyle(KindredPressStyle())
                                .disabled(draft.trimmed.isEmpty || draft.trimmed.count > 2000).accessibilityLabel("Save demo message").accessibilityIdentifier("sendMessage")
                        }
                        Group {
                            Text(draft.trimmed.count > 2000 ? "Keep your message to 2,000 characters." : "Demo chat · Nothing is sent; replies are not generated.").font(.caption2).foregroundStyle(Color.muted)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 10).background(Color.paper)
                }
            } else {
                EmptyState(symbol: "hand.raised", title: "Conversation unavailable", message: "This connection has ended or the profile was blocked. The chat is no longer available.")
            }
        }.background(Color.paper).navigationTitle(conversation.flatMap { store.member($0.memberID)?.name } ?? "Conversation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let conversation { ToolbarItem(placement: .topBarTrailing) { SafetyMenu(memberID: conversation.memberID) } }
                if composing {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { composing = false } }
                }
            }
            .alert("Replace your draft?", isPresented: Binding(get: { pendingStarter != nil }, set: { if !$0 { pendingStarter = nil } })) {
                Button("Use suggestion") { if let text = pendingStarter { useStarter(text) }; pendingStarter = nil }
                Button("Keep my draft", role: .cancel) { pendingStarter = nil }
            } message: { Text("The suggestion only fills the composer. Nothing is sent until you tap the send button.") }
    }
    private func useStarter(_ text: String) {
        draft = text
        showStarters = false
        composing = true
    }
    private func starterIdeas(_ profile: MemberProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start with their story").font(.headline)
            Text("Choose an idea, then make it your own.").font(.subheadline).foregroundStyle(Color.muted)
            ForEach(Array(profile.conversationStarters.enumerated()), id: \.element.id) { index, starter in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(starter.question).font(.caption.weight(.semibold)).foregroundStyle(Color.plum)
                    Text(starter.answer).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Button("Ask about this") {
                        if draft.trimmed.isEmpty { useStarter(starter.draft) }
                        else { pendingStarter = starter.draft }
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .accessibilityLabel("Ask about \(starter.question)")
                        .accessibilityHint("Fills a draft for you to edit. Does not send it.")
                        .accessibilityIdentifier("starter-\(starter.id)")
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.sand, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct MessageBubble: View {
    let message: Message
    let memberName: String
    private var outgoing: Bool { message.senderID == "me" }
    var body: some View {
        HStack {
            if outgoing { Spacer(minLength: 35) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 6) {
                Text(message.text).font(.body).padding(16).foregroundStyle(outgoing ? Color.onPlum : Color.ink)
                    .background(outgoing ? Color.plum : Color.surface, in: RoundedRectangle(cornerRadius: 22))
                HStack(spacing: 5) {
                    Text(message.createdAt, style: .time)
                    if outgoing { Text("· saved locally") }
                }.font(.caption2).foregroundStyle(Color.muted)
            }
            if !outgoing { Spacer(minLength: 35) }
        }.accessibilityElement(children: .combine).accessibilityLabel("\(outgoing ? "You" : memberName): \(message.text). \(message.createdAt.formatted(date: .abbreviated, time: .shortened)). \(outgoing ? "Saved locally" : "Sample message")")
    }
}

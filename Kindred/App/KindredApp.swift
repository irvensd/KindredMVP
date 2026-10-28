import SwiftUI

@main
struct KindredApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(Color.plum).modifier(PrototypeAccessibilityChecks())
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--demo") { store.hasCompletedOnboarding = true }
                    #endif
                }
        }
    }
}
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.kindredReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var store = store
        Group {
            if store.hasCompletedOnboarding { MainTabs() }
            else if store.isOnboarding { OnboardingView() }
            else { WelcomeView() }
        }
        .foregroundStyle(Color.ink).background(Color.paper)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.hasCompletedOnboarding)
        .sensoryFeedback(.success, trigger: store.feedbackCount)
        .overlay(alignment: .top) {
            if let feedback = store.feedback {
                Text(feedback).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .foregroundStyle(Color.onPlum).background(Color.plum, in: Capsule()).padding(.horizontal, 24).padding(.top, 5)
                    .accessibilityIdentifier("feedbackBanner").allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: store.feedbackCount) {
                        UIAccessibility.post(notification: .announcement, argument: feedback)
                        try? await Task.sleep(for: .seconds(3))
                        if !Task.isCancelled { store.feedback = nil }
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.feedback)
        .alert("Let's check that", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
struct MainTabs: View {
    @Environment(AppStore.self) private var store
    private enum Destination: Hashable { case discover, likes, chats, you }
    @State private var selectedTab = Destination.discover
    @State private var chatPath: [String] = []
    @State private var pendingConversation: String?
    var body: some View {
        @Bindable var store = store
        TabView(selection: $selectedTab) {
            Tab("Discover", systemImage: "sparkles", value: Destination.discover) { NavigationStack { DiscoverView() } }
            Tab("Likes", systemImage: "heart", value: Destination.likes) { NavigationStack { LikesView() } }
            Tab("Chats", systemImage: "bubble.left.and.bubble.right", value: Destination.chats) {
                NavigationStack(path: $chatPath) {
                    ChatsView().navigationDestination(for: String.self) { ConversationView(conversationID: $0) }
                }
            }.badge(store.conversations.reduce(0) { $0 + $1.unreadCount })
            Tab("You", systemImage: "person.crop.circle", value: Destination.you) { NavigationStack { YouView() } }
        }.tint(Color.plum)
            .fullScreenCover(item: $store.presentedMatch, onDismiss: {
                if let id = pendingConversation {
                    pendingConversation = nil
                    guard store.conversations.contains(where: { $0.id == id }) else { return }
                    chatPath = [id]; selectedTab = .chats
                }
            }) { match in
                MatchCelebrationView(match: match, sayHello: {
                    pendingConversation = store.conversations.first { $0.memberID == match.memberID }?.id
                    store.presentedMatch = nil
                }, keepDiscovering: {
                    selectedTab = .discover
                    store.presentedMatch = nil
                })
            }
    }
}

/// Debug-only launch controls exercise the same environment branches as system settings.
private struct PrototypeAccessibilityChecks: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        content
            .transformEnvironment(\.dynamicTypeSize) { value in
                if ProcessInfo.processInfo.arguments.contains("--large-text") { value = .accessibility3 }
            }
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
        #else
        content
        #endif
    }
}

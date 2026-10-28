import SwiftUI

struct MatchCelebrationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.kindredReduceMotion) private var reduceMotion
    let match: Match
    let sayHello: () -> Void
    let keepDiscovering: () -> Void
    @State private var appeared = false
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !typeSize.isAccessibilitySize {
                    BrandMark(size: 36).padding(.top, 32)
                    Overline(text: "A feeling, returned")
                }
                if let member = store.member(match.memberID) {
                    let portraitLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    portraitLayout {
                        portrait(store.state.currentProfile)
                        if !typeSize.isAccessibilitySize {
                            Image(systemName: "sparkles").font(.title2).foregroundStyle(Color.plum)
                                .padding(.top, 42).accessibilityHidden(true)
                        }
                        portrait(member)
                    }.scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                    Text("A little spark, shared.").font(.largeTitle.weight(.semibold)).tracking(-1)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("matchTitle")
                    Text("You and \(member.name) have both shown interest. A good conversation could be next.")
                        .font(.title3).foregroundStyle(Color.muted)
                    if let detail = store.savedInterests(for: member.id).first {
                        SavedInterestDetail(detail: detail).multilineTextAlignment(.leading)
                            .padding(18).background(Color.sand, in: RoundedRectangle(cornerRadius: 22))
                            .accessibilityIdentifier("matchSavedInterest")
                    }
                    NoteCard(symbol: "sparkles", text: "A simulated mutual match between demo profiles. No one was notified, and nothing will be sent.")
                }
            }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(28)
        }.background(Color.paper)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    PrimaryButton(title: "Say hello", symbol: typeSize.isAccessibilitySize ? nil : "bubble.left", action: sayHello).accessibilityIdentifier("matchSayHello")
                    Button("Keep discovering", action: keepDiscovering).font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityIdentifier("matchKeepDiscovering")
                }.padding(24).background(Color.paper)
            }
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { appeared = true } }
    }
    private func portrait(_ profile: MemberProfile) -> some View {
        VStack(spacing: 12) {
            Avatar(profile: profile, size: 108)
                .overlay(Circle().stroke(Color.plum.opacity(0.15), lineWidth: 3))
            Text(profile.name).font(.headline).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }
}

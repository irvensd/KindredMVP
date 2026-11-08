import SwiftUI

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @State private var accountMode: BackendAccountView.Mode?
    @State private var completedAccount: (String, BackendAccount.Session, BackendAccount.DiscoveryProfile?)?
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                HStack(spacing: 9) {
                    BrandMark(size: 25)
                    Text("kindred").font(.system(.title, design: .rounded, weight: .semibold)).tracking(-1)
                }.padding(.top, 26)
                ZStack {
                    RoundedRectangle(cornerRadius: 150).fill(Color.sand).frame(width: 265, height: 310).rotationEffect(.degrees(-12))
                    HStack(spacing: -24) {
                        PhotoView(photo: DemoData.people[1].photos.first).frame(width: 170, height: 245).clipShape(RoundedRectangle(cornerRadius: 90)).rotationEffect(.degrees(-10)).offset(y: 22)
                        PhotoView(photo: DemoData.people[0].photos.first).frame(width: 183, height: 280).clipShape(RoundedRectangle(cornerRadius: 95)).rotationEffect(.degrees(9)).offset(y: -10)
                    }
                    Image(systemName: "sparkle").font(.system(size: 34, weight: .light)).foregroundStyle(Color.plum).offset(x: -140, y: -130)
                    Text("Something real starts here.").font(.caption.weight(.medium)).padding(.horizontal, 18).padding(.vertical, 11).background(Color.surface, in: Capsule()).rotationEffect(.degrees(-5)).offset(y: 137)
                }.frame(height: 335).accessibilityElement(children: .ignore).accessibilityLabel("Two fictional adults, smiling. AI-generated sample portraits.")
                VStack(spacing: 14) {
                    Overline(text: "A little faith. A little spark.")
                    Text("Shared faith.\nGenuine connection.").font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1.1).multilineTextAlignment(.center)
                    Text("Meet Adventist singles who share your values — and bring something beautifully their own.")
                        .font(.body).foregroundStyle(Color.muted).multilineTextAlignment(.center).padding(.horizontal, 8)
                }
                VStack(spacing: 10) {
                    PrimaryButton(title: "Create account", symbol: "arrow.right") { accountMode = .create }
                    Button("Sign in") { accountMode = .signIn }
                        .font(.headline).frame(minHeight: 44)
                    Button("Explore the demo") { store.startDemoOnboarding() }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                        .accessibilityIdentifier("getStarted")
                    Text("18+ · Demo profiles and activity are fictional.")
                        .font(.caption).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }.background(Color.paper).sheet(item: $accountMode, onDismiss: {
            guard let (name, session, profile) = completedAccount else { return }
            completedAccount = nil
            store.openAccount(displayName: name, session: session, profile: profile)
        }) { mode in
            BackendAccountView(mode: mode) { name, session, profile in
                completedAccount = (name, session, profile)
                accountMode = nil
            }.tint(Color.plum)
        }
    }
}

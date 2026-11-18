import SwiftUI

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var accountMode: BackendAccountView.Mode?
    @State private var completedAccount: (String, BackendAccount.Session, BackendAccount.DiscoveryProfile?, Bool)?
    var body: some View {
        GeometryReader { viewport in
            let portraitScale = min(1, viewport.size.width / 385, viewport.size.height / 790)
            ScrollView {
                VStack(spacing: 18) {
                    wordmark
                    if !typeSize.isAccessibilitySize {
                        portraitPair(scale: portraitScale)
                    }
                    introduction
                    accountActions
                    if typeSize.isAccessibilitySize {
                        portraitPair(scale: portraitScale)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height)
            }
        }
        .background(Color.paper).sheet(item: $accountMode, onDismiss: {
            guard let (name, session, profile, staffOnly) = completedAccount else { return }
            completedAccount = nil
            store.openAccount(displayName: name, session: session, profile: profile, staffOnly: staffOnly)
        }) { mode in
            BackendAccountView(mode: mode) { name, session, profile, staffOnly in
                completedAccount = (name, session, profile, staffOnly)
                accountMode = nil
            }.tint(Color.plum)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            BrandMark(size: 25)
            Text("kindred")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .tracking(-1)
        }
    }

    private func portraitPair(scale: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 130 * scale)
                .fill(Color.sand)
                .frame(width: 242 * scale, height: 268 * scale)
                .rotationEffect(.degrees(-12))
            HStack(spacing: -24 * scale) {
                PhotoView(photo: DemoData.people[1].photos.first)
                    .frame(width: 159 * scale, height: 223 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 83 * scale))
                    .rotationEffect(.degrees(-10))
                    .offset(y: 17 * scale)
                PhotoView(photo: DemoData.people[0].photos.first)
                    .frame(width: 172 * scale, height: 258 * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 90 * scale))
                    .rotationEffect(.degrees(9))
                    .offset(y: -7 * scale)
            }
            Image(systemName: "sparkle")
                .font(.system(size: 28 * scale, weight: .light))
                .foregroundStyle(Color.plum)
                .offset(x: -130 * scale, y: -106 * scale)
        }
        .frame(height: 294 * scale)
        .accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(spacing: 8) {
            Text("Shared faith.\nGenuine connection.")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .tracking(-1.1)
                .accessibilityAddTraits(.isHeader)
            Text("Dating for Seventh-day Adventist singles.")
                .font(.body)
                .foregroundStyle(Color.muted)
        }
        .multilineTextAlignment(.center)
    }

    private var accountActions: some View {
        VStack(spacing: 6) {
            PrimaryButton(title: "Create account", symbol: "arrow.right") { accountMode = .create }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    signInButton
                    demoButton
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 0) {
                    signInButton
                    demoButton
                }
            }
            Text("18+ · Demo profiles and activity are fictional.")
                .font(.caption)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }
    }

    private var signInButton: some View {
        Button {
            accountMode = .signIn
        } label: {
            Text("Sign in")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("openAccountSignIn")
    }

    private var demoButton: some View {
        Button {
            store.startDemoOnboarding()
        } label: {
            Text("Explore the demo")
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("getStarted")
    }

}

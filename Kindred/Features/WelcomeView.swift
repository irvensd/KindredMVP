import SwiftUI

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showSignIn = false
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
                    PrimaryButton(title: "Get Started", symbol: "arrow.right") { store.isOnboarding = true }.accessibilityIdentifier("getStarted")
                    Button("Already have an account? Sign in") { showSignIn = true }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    Text("18+ · Private, in-memory prototype\nFictional members. No real accounts or connections.")
                        .font(.caption).foregroundStyle(Color.muted).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }.background(Color.paper).sheet(isPresented: $showSignIn) {
            NavigationStack {
                VStack(spacing: 24) {
                    BrandMark(size: 48)
                    Text("Your next chapter\nstarts here.").font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
                    Text("Authentication preview").font(.headline)
                    Text("Sign-in is unavailable in Phase 1. No credentials are collected. You can explore fictional profiles in a fresh, local demo session.").foregroundStyle(Color.muted).multilineTextAlignment(.center)
                    PrimaryButton(title: "Explore the demo", symbol: "sparkles") { showSignIn = false; store.hasCompletedOnboarding = true }
                }.padding(28).frame(maxHeight: .infinity).background(Color.paper)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showSignIn = false } } }
            }.presentationDetents([.large])
        }
    }
}

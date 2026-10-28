import SwiftUI

/// Horizontal intent changes the introduction; vertical drags keep the page scrollable.
/// Photo paging uses explicit arrows here to avoid two meanings for the same swipe.
struct DiscoveryPortrait: View {
    @Environment(\.kindredReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let profile: MemberProfile
    let isLiked: Bool
    let next: () -> Void
    let interested: () -> Void
    @State private var portraitWidth: CGFloat = 350
    @State private var swipe = DiscoverySwipe()
    @State private var trackingDrag = false
    @GestureState private var dragIsActive = false
    private var ready: Bool { swipe.isReady(width: portraitWidth, isLiked: isLiked) }
    private var offset: CGFloat { reduceMotion ? 0 : swipe.offset(width: portraitWidth) }
    private var feedback: String {
        if swipe.translation < 0 { return ready ? "Release for next" : "Next introduction" }
        if isLiked { return "Already interested" }
        return ready ? "Release to save" : "I'm interested"
    }

    var body: some View {
        VStack(spacing: 12) {
            PhotoGallery(profile: profile, aspectRatio: 0.9, allowsPaging: false)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { portraitWidth = $0 }
                .overlay {
                    if abs(swipe.translation) > 14 {
                        Label(feedback, systemImage: swipe.translation < 0 ? "arrow.right" : isLiked ? "checkmark" : "sparkles")
                            .font(.headline).multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .foregroundStyle(Color.onPlum).background(Color.plum, in: Capsule())
                            .opacity(min(1, Double(abs(swipe.translation) / DiscoverySwipe.threshold(width: portraitWidth))))
                            .padding(.horizontal, 16)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .offset(x: offset)
                .rotationEffect(.degrees(Double(offset / 70)))
                .scaleEffect(1 - min(abs(offset) / 6000, 0.015))
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discoveryPortrait")
                .accessibilityAction(named: "Next introduction") { next() }
                .accessibilityAction(named: "Save interest") { if !isLiked { interested() } }
                .simultaneousGesture(
                    // Global translation is stable while the photo moves beneath the finger.
                    DragGesture(minimumDistance: 14, coordinateSpace: .global)
                        .updating($dragIsActive) { _, active, _ in active = true }
                        .onChanged { value in
                            if !trackingDrag {
                                swipe = DiscoverySwipe()
                                trackingDrag = true
                            }
                            swipe.update(value.translation, width: portraitWidth, isLiked: isLiked)
                        }
                        .onEnded { value in
                            let action = swipe.action(at: value.translation, predicted: value.predictedEndTranslation,
                                                      velocity: value.velocity, width: portraitWidth, isLiked: isLiked)
                            settle()
                            switch action {
                            case .next: next()
                            case .interested: interested()
                            case nil: break
                            }
                        }
                )
                .onChange(of: dragIsActive) { _, active in
                    guard !active else { return }
                    trackingDrag = false
                    // Cancellation has no onEnded callback. Defer cleanup so a normal
                    // release can first consume its intent; never reset a new drag.
                    Task { @MainActor in
                        await Task.yield()
                        if !dragIsActive { settle() }
                    }
                }
                .sensoryFeedback(.selection, trigger: swipe.didReachThreshold) { _, reached in reached }
                .transaction { if reduceMotion { $0.animation = nil } }
            if !typeSize.isAccessibilitySize {
                Text("Swipe left for next · right if interested")
                    .font(.caption).foregroundStyle(Color.muted).accessibilityHidden(true)
            }
        }
    }
    private func settle() {
        trackingDrag = false
        guard swipe.axis != .undecided || swipe.translation != 0 else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.90)) {
            swipe = DiscoverySwipe()
        }
    }

}

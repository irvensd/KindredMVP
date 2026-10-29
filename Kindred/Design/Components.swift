import SwiftUI

extension Color {
    static let paper = Color("Paper")
    static let ink = Color("Ink")
    static let plum = Color("Plum")
    static let rose = Color("Rose")
    static let sand = Color("Sand")
    static let muted = Color("Secondary")
    static let surface = Color("Surface")
    static let onPlum = Color("OnPlum")
}
struct BrandMark: View {
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: size, weight: .light))
            .rotationEffect(.degrees(-35))
            .foregroundStyle(Color.plum)
            .accessibilityHidden(true)
    }
}
struct Overline: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Color.plum) }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(title).font(.headline)
                if let symbol { Image(systemName: symbol) }
                Spacer(minLength: 0)
            }.padding(.vertical, 17).padding(.horizontal, 20).contentShape(Capsule())
        }.buttonStyle(.plain).foregroundStyle(Color.onPlum).background(Color.plum, in: Capsule())
    }
}
struct SampleBadge: View {
    var text = "FICTIONAL PROFILE"
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).tracking(1)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(Color.ink).background(Color.paper.opacity(0.96), in: Capsule())
    }
}
struct PhotoView: View {
    let photo: ProfilePhoto?
    var body: some View {
        GeometryReader { proxy in
            let image = photo?.localData.flatMap { UIImage(data: $0) } ?? photo?.assetName.flatMap { UIImage(named: $0) }
            if let image {
                let zoom = min(3, max(1, photo?.cropZoom ?? 1))
                let scale = max(proxy.size.width / image.size.width, proxy.size.height / image.size.height) * zoom
                let width = image.size.width * scale
                let height = image.size.height * scale
                Image(uiImage: image).resizable()
                    .frame(width: width, height: height)
                    .offset(x: -max(-1, min(1, photo?.cropX ?? 0)) * (width - proxy.size.width) / 2,
                            y: -max(-1, min(1, photo?.cropY ?? 0)) * (height - proxy.size.height) / 2)
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else {
                ZStack { Color.sand; Image(systemName: "person.crop.rectangle").font(.largeTitle).foregroundStyle(Color.plum) }
            }
        }.accessibilityLabel(photo?.caption ?? "Add a profile photo").accessibilityAddTraits(.isImage)
    }
}
struct Avatar: View {
    let profile: MemberProfile
    var size: CGFloat = 58
    var body: some View { PhotoView(photo: profile.photos.first).frame(width: size, height: size).clipShape(Circle()).accessibilityLabel(profile.name) }
}
struct PhotoGallery: View {
    @Environment(\.kindredReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let profile: MemberProfile
    var showIdentity = true
    var aspectRatio: CGFloat = 0.79
    var allowsPaging = true
    @State private var selection = 0
    @State private var photoDirection: CGFloat = 1
    private var currentPhoto: ProfilePhoto? { profile.photos.indices.contains(selection) ? profile.photos[selection] : nil }
    private var photoDescription: String {
        profile.photos.isEmpty ? "\(profile.name), no profile photos" : "\(profile.name), photo \(selection + 1) of \(profile.photos.count)"
    }
    private var photoTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: photoDirection * 10)),
            removal: .opacity.combined(with: .offset(x: -photoDirection * 10))
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                if allowsPaging && !profile.photos.isEmpty {
                    TabView(selection: $selection) {
                        ForEach(Array(profile.photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoView(photo: photo).tag(index)
                                .accessibilityLabel("\(profile.name), photo \(index + 1) of \(profile.photos.count)")
                                .accessibilityValue(photo.caption)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                        .accessibilityIdentifier("profilePhotoPager")
                } else {
                    ZStack {
                        PhotoView(photo: currentPhoto)
                            .id(selection).transition(photoTransition)
                            .accessibilityLabel(photoDescription)
                            .accessibilityValue(currentPhoto?.caption ?? "")
                            .accessibilityAction(named: "Next photo") { changePhoto(1) }
                            .accessibilityAction(named: "Previous photo") { changePhoto(-1) }
                    }.animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: selection)
                }
                if !typeSize.isAccessibilitySize {
                    LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.85)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
                    identity(color: .white).padding(24).padding(.bottom, 4).allowsHitTesting(false)
                }
                VStack {
                    HStack(alignment: .top, spacing: 8) {
                        if profile.isDemo && !typeSize.isAccessibilitySize { SampleBadge().fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 0)
                        if profile.photos.count > 1 { photoNavigation }
                    }.padding(16)
                    Spacer()
                }
            }.aspectRatio(aspectRatio, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 28))
            if typeSize.isAccessibilitySize {
                if profile.isDemo { SampleBadge() }
                identity(color: .ink)
            }
            if profile.id != "me", let photo = currentPhoto {
                HStack {
                    Spacer(minLength: 0)
                    PhotoInterestButton(profile: profile, photo: photo)
                }
            }
        }
        .onChange(of: profile.id) { _, _ in selection = 0; photoDirection = 1 }
        .onChange(of: profile.photos.count) { _, count in selection = max(0, min(selection, count - 1)) }
        .onChange(of: selection) { _, value in
            if UIAccessibility.isVoiceOverRunning && !profile.photos.isEmpty {
                UIAccessibility.post(notification: .announcement, argument: "Photo \(value + 1) of \(profile.photos.count)")
            }
        }
    }
    private var photoNavigation: some View {
        HStack(spacing: 0) {
            photoArrow(forward: false)
            Text("\(selection + 1) / \(profile.photos.count)")
                .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.plum)
                .fixedSize().frame(minWidth: 38)
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(selection + 1)))
                .accessibilityLabel("Photo \(selection + 1) of \(profile.photos.count)")
                .accessibilityIdentifier("photoPosition")
            photoArrow(forward: true)
        }.fixedSize()
            .background(Color.paper.opacity(0.9), in: Capsule())
            .glassEffect(.regular, in: Capsule())
    }
    private func photoArrow(forward: Bool) -> some View {
        let available = forward ? selection < profile.photos.count - 1 : selection > 0
        return Button { changePhoto(forward ? 1 : -1) } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.plum.opacity(available ? 1 : 0.32))
                .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(PhotoNavigationPressStyle()).disabled(!available)
            .accessibilityLabel(forward ? "Next photo" : "Previous photo")
            .accessibilityHint(available ? "Shows \(profile.name)'s \(forward ? "next" : "previous") photo." : (forward ? "Last photo." : "First photo."))
    }
    private func changePhoto(_ delta: Int) {
        let target = max(0, min(profile.photos.count - 1, selection + delta))
        guard target != selection else { return }
        photoDirection = delta > 0 ? 1 : -1
        var transaction = Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.28))
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) { selection = target }
    }
    private func identity(color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showIdentity {
                Text("\(profile.name), \(profile.age)").font(.largeTitle.weight(.semibold))
                Label(profile.city, systemImage: "mappin.and.ellipse").font(.subheadline)
            }
            Text(selection == 0 ? profile.occupation : "A glimpse of the little things")
                .font(.footnote).contentTransition(reduceMotion ? .identity : .opacity)
        }.foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}
private struct PhotoNavigationPressStyle: ButtonStyle {
    @Environment(\.kindredReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.plum.opacity(configuration.isPressed ? 0.12 : 0), in: Circle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// An explicit photo action keeps profile swipes and photo interest unambiguous.
struct PhotoInterestButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.kindredReduceMotion) private var reduceMotion
    let profile: MemberProfile
    let photo: ProfilePhoto
    var location = "gallery"
    private var saved: Bool { store.isPhotoLiked(photo.id, memberID: profile.id) }
    private var photoName: String {
        "\(profile.name)’s photo \((profile.photos.firstIndex { $0.id == photo.id } ?? 0) + 1)"
    }
    var body: some View {
        Button { store.like(profile.id, photoID: photo.id) } label: {
            Label(saved ? "Photo saved" : "Like this photo", systemImage: saved ? "checkmark" : "sparkles")
                .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 15).padding(.vertical, 8).frame(minHeight: 44)
                .background(Color.surface, in: Capsule())
        }.buttonStyle(InterestSaveButtonStyle()).foregroundStyle(Color.plum).disabled(saved)
            .accessibilityLabel("\(saved ? "Saved" : "Like") \(photoName)")
            .accessibilityHint(saved ? "Saved in Your likes." : "Saves interest in this photo. No message is sent.")
            .accessibilityIdentifier("photoLike-\(profile.id)-\(photo.id)-\(location)")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: saved)
    }
}

/// Saved labels remain legible while disabled; only an active press fades.
struct InterestSaveButtonStyle: ButtonStyle {
    @Environment(\.kindredReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SavedInterestDetail: View {
    let detail: SavedInterest
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let photo = detail.photo {
                HStack(alignment: .center, spacing: 14) {
                    PhotoView(photo: photo).frame(width: 60, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("You noticed").font(.caption).foregroundStyle(Color.muted)
                        Text(detail.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.plum)
                    }
                }
            } else {
                Text("You connected with").font(.caption).foregroundStyle(Color.muted)
                Text(detail.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.plum)
                if let answer = detail.answer {
                    Text("“\(answer)”").font(.subheadline).foregroundStyle(Color.ink)
                }
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, width: proposal.width ?? 320).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(subviews[index].sizeThatFits(.unspecified).width, bounds.width), height: nil))
        }
    }
    private func layout(subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(natural.width, width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
struct InterestChips: View {
    let interests: Set<Interest>
    var body: some View {
        FlowLayout {
            ForEach(Interest.allCases.filter { interests.contains($0) }) { item in
                Label(item.rawValue, systemImage: item.symbol).font(.subheadline)
                    .padding(.horizontal, 13).padding(.vertical, 10).background(Color.sand, in: Capsule())
            }
        }
    }
}
struct InterestPicker: View {
    @Binding var selected: Set<Interest>
    var body: some View {
        FlowLayout {
            ForEach(Interest.allCases) { item in
                Button {
                    if selected.contains(item) { selected.remove(item) } else if selected.count < 8 { selected.insert(item) }
                } label: {
                    Label(item.rawValue, systemImage: selected.contains(item) ? "checkmark" : item.symbol)
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 13)
                        .foregroundStyle(selected.contains(item) ? Color.onPlum : Color.ink)
                        .background(selected.contains(item) ? Color.plum : Color.sand, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(item) ? .isSelected : [])
            }
        }
        Text("\(selected.count) of 8 selected · optional").font(.footnote).foregroundStyle(Color.muted)
    }
}
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(Color.plum).padding(24).background(Color.sand, in: Circle())
            Text(title).font(.title2.weight(.semibold))
            Text(message).font(.body).foregroundStyle(Color.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
    }
}
struct PageHeader: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !typeSize.isAccessibilitySize { Overline(text: eyebrow) }
            Text(title).font(.largeTitle.weight(.semibold)).tracking(-1)
            Text(subtitle).font(.subheadline).foregroundStyle(Color.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct NoteCard: View {
    let symbol: String
    let text: String
    var body: some View {
        Label { Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(Color.plum) }
            .foregroundStyle(Color.muted).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.sand.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
}

// Read the system preference in production; allow a deterministic Debug UI check.
extension EnvironmentValues {
    var kindredReduceMotion: Bool {
        #if DEBUG
        accessibilityReduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        #else
        accessibilityReduceMotion
        #endif
    }
}

/// Hidden navigation headers need their own status-area background while content scrolls.
/// This overlay follows the actual safe area without changing layout or intercepting touches.
struct StatusAreaProtection: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { geometry in
                Color.paper
                    .frame(height: geometry.safeAreaInsets.top)
                    .offset(y: -geometry.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Bridges attempted interactive sheet dismissal on iOS 26, which lacks SwiftUI's
/// dismissalConfirmationDialog. Programmatic Save/Discard dismissal remains available.
struct SheetDismissalGuard: UIViewControllerRepresentable {
    var hasChanges: Bool
    var onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hasChanges = hasChanges
        controller.onAttempt = onAttempt
        controller.install()
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var hasChanges = false
        var onAttempt: () -> Void = { }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            install()
        }
        func install() {
            // presentingViewController can be inherited by child controllers;
            // install on the actual sheet root, not the embedded bridge.
            var sheet: UIViewController = self
            while let parent = sheet.parent { sheet = parent }
            guard sheet.presentingViewController != nil else { return }
            sheet.presentationController?.delegate = self
            sheet.isModalInPresentation = hasChanges
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { !hasChanges }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { onAttempt() }
    }
}

struct ProfileFieldError: View {
    let message: String?
    let field: String
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(Color.plum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profileError-" + field)
        }
    }
}

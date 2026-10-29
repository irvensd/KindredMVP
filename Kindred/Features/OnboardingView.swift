import SwiftUI
import PhotosUI
import ImageIO

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.kindredReduceMotion) private var reduceMotion
    @State private var validation: String?
    private let titles = ["A little hello.", "Your kind of\nconnection.", "Close by.\nLooking ahead.", "A face to\nyour name."]
    private let subtitles = ["Just the essentials to get started. Your birthday stays private; only your age appears on your profile.", "Choose your gender and who you'd like to meet.", "A general city and an honest intention are a good place to start.", "Choose a photo and take a quick look. Your interests, faith story and prompts can come later."]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("LET'S GET ACQUAINTED").font(.caption.weight(.semibold)).tracking(1)
                    Spacer()
                    Text("\(store.onboardingStep + 1) of \(OnboardingDraft.stepCount)").font(.caption.monospacedDigit())
                }.foregroundStyle(Color.muted).padding(.horizontal, 24).padding(.bottom, 12)
                ProgressView(value: Double(store.onboardingStep + 1), total: Double(OnboardingDraft.stepCount)).tint(Color.plum).padding(.horizontal, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(titles[store.onboardingStep]).font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
                            Text(subtitles[store.onboardingStep]).foregroundStyle(Color.muted)
                        }
                        stepContent
                    }.padding(24)
                }.scrollDismissesKeyboard(.interactively).id(store.onboardingStep)
                VStack(spacing: 10) {
                    if let validation {
                        Label(validation, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color.plum).accessibilityIdentifier("onboardingError")
                    }
                    PrimaryButton(title: store.onboardingStep == OnboardingDraft.stepCount - 1 ? "Start discovering" : "Continue", symbol: "arrow.right") { next() }.accessibilityIdentifier("onboardingNext")
                    Text("This session only. Nothing is uploaded.").font(.caption2).foregroundStyle(Color.muted)
                }.padding(.horizontal, 24).padding(.vertical, 12).background(Color.paper)
            }.background(Color.paper).navigationBarTitleDisplayMode(.inline)
                .onChange(of: store.onboarding.validationError(step: store.onboardingStep)) { _, error in
                    if validation != nil { validation = error }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismissKeyboard(); validation = nil
                            if store.onboardingStep > 0 { store.onboardingStep -= 1 } else { store.isOnboarding = false }
                        } label: { Image(systemName: "arrow.left").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Back")
                    }
                    ToolbarItem(placement: .principal) { HStack(spacing: 6) { BrandMark(size: 18); Text("kindred").font(.system(.headline, design: .rounded)) } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { dismissKeyboard() } }
                }
        }
    }
    @ViewBuilder private var stepContent: some View {
        @Bindable var store = store
        switch store.onboardingStep {
        case 0:
            VStack(alignment: .leading, spacing: 18) {
                TextField("First name", text: $store.onboarding.name).textContentType(.givenName).font(.title2).padding(18).background(Color.surface, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("firstName")
                DatePicker("Birth date", selection: $store.onboarding.birthDate, in: ...Date(), displayedComponents: .date).accessibilityIdentifier("birthDate")
                Toggle("I am 18 or older", isOn: $store.onboarding.acknowledgedAdult).font(.headline).padding(18).background(Color.surface, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("adultAcknowledgment")
                Text("Be kind. Respect boundaries. This is a local prototype for adults, with fictional members and no real connections.").font(.footnote).foregroundStyle(Color.muted)
            }
        case 1:
            VStack(alignment: .leading, spacing: 22) {
                Text("I am").font(.headline)
                selectionRows(Gender.allCases, selected: store.onboarding.gender) { store.onboarding.gender = $0 }
                Text("I'd like to meet").font(.headline)
                GenderChoices(selected: $store.onboarding.genders)
            }
        case 2:
            VStack(alignment: .leading, spacing: 22) {
                TextField("City or general area", text: $store.onboarding.city).textContentType(.addressCity).padding(18).background(Color.surface, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("city")
                Text("I'm looking for").font(.headline)
                selectionRows(Intention.allCases, selected: store.onboarding.intention) { store.onboarding.intention = $0 }
                DisclosureGroup("Within \(store.onboarding.radiusMiles) miles · adjust") { RadiusControl(value: $store.onboarding.radiusMiles).padding(.top, 12) }
                Text("No precise location needed. Demo distances are sample values around Chicago.").font(.footnote).foregroundStyle(Color.muted)
            }
        default:
            PhotoEditor(photos: $store.onboarding.photos)
            if !store.onboarding.photos.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your first impression").font(.headline)
                    HStack(spacing: 16) {
                        Avatar(profile: store.onboarding.profile(), size: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(store.onboarding.name.trimmed), \(OnboardingDraft.age(on: Date(), birthDate: store.onboarding.birthDate))").font(.title2.weight(.semibold))
                            Text(store.onboarding.city.trimmed).foregroundStyle(Color.muted)
                            Text(store.onboarding.intention?.rawValue ?? "").font(.footnote).foregroundStyle(Color.plum)
                        }
                    }
                    Text("Make it yours anytime in You → Edit profile.").font(.footnote).foregroundStyle(Color.muted)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.surface, in: RoundedRectangle(cornerRadius: 22)).accessibilityIdentifier("onboardingPreview")
            }
        }
    }
    private func next() {
        dismissKeyboard()
        if let error = store.onboarding.validationError(step: store.onboardingStep) { validation = error; return }
        validation = nil
        if store.onboardingStep == OnboardingDraft.stepCount - 1 { _ = store.completeOnboarding() }
        else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.onboardingStep += 1 } }
    }
    private func selectionRows<T: RawRepresentable & Identifiable & Equatable>(_ values: [T], selected: T?, action: @escaping (T) -> Void) -> some View where T.RawValue == String {
        VStack(spacing: 12) {
            ForEach(values) { value in
                Button { action(value) } label: {
                    HStack { Text(value.rawValue); Spacer(); Image(systemName: selected == value ? "checkmark.circle.fill" : "circle") }
                        .font(.headline).padding(18).foregroundStyle(selected == value ? Color.onPlum : Color.ink)
                        .background(selected == value ? Color.plum : Color.surface, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).accessibilityAddTraits(selected == value ? .isSelected : [])
            }
        }
    }
}
struct GenderChoices: View {
    @Binding var selected: Set<Gender>
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Gender.allCases) { gender in
                Toggle(gender.rawValue, isOn: Binding(get: { selected.contains(gender) }, set: { if $0 { selected.insert(gender) } else { selected.remove(gender) } }))
                    .padding(16).background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}
struct RadiusControl: View {
    @Binding var value: Int
    var showsPreciseAdjustment = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discovery radius").font(.headline)
            Text("Within \(value) miles")
                .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Color.plum)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("radiusSummary")
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) }), in: 5...250, step: 5)
                .accessibilityLabel("Discovery radius").accessibilityValue("\(value) miles")
                .accessibilityHint("Adjusts in five-mile steps, from 5 to 250 miles.")
            HStack {
                Text("5 mi")
                Spacer()
                Text("250 mi")
            }.font(.caption).foregroundStyle(Color.muted).monospacedDigit().accessibilityHidden(true)
            if showsPreciseAdjustment {
                Stepper("Adjust by 5 miles", value: $value, in: 5...250, step: 5)
                    .font(.subheadline)
                    .accessibilityLabel("Discovery radius, five-mile adjustment")
                    .accessibilityValue("\(value) miles")
                    .accessibilityIdentifier("radiusAdjustment")
            }
        }.padding(.vertical, 4)
    }
}
struct FaithEditor: View {
    @Binding var faith: FaithPreferences
    var validationMessage: String? = nil
    var body: some View {
        Group {
            VStack(alignment: .leading) {
                Text("My Sabbath rhythm").font(.headline)
                Picker("Sabbath rhythm", selection: $faith.sabbath) { ForEach(SabbathPractice.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
            }
            VStack(alignment: .leading) {
                Text("Around the table").font(.headline)
                Picker("Food preference", selection: $faith.food) { ForEach(FoodPreference.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
            }
            VStack(alignment: .leading, spacing: 8) {
            Text("What faith means to me (optional)").font(.headline)
            TextField("Your own words", text: $faith.meaning, axis: .vertical).lineLimit(3...6).padding(16).background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
            ProfileFieldError(message: validationMessage, field: "faith")
            }.id("faith")
            Text("Shared values are a conversation, never a score.").font(.footnote).foregroundStyle(Color.muted)
        }
    }
}
struct PromptEditor: View {
    @Binding var prompts: [ProfilePrompt]
    var issues: [ProfileValidationIssue] = []
    var body: some View {
        Group {
            ForEach($prompts) { $prompt in
                VStack(alignment: .leading, spacing: 10) {
                    Text(prompt.question).font(.headline)
                    TextField("A little glimpse of you…", text: $prompt.answer, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("prompt-\(prompt.id)")
                    Text("\(prompt.answer.count)/240").font(.caption).foregroundStyle(Color.muted)
                    ProfileFieldError(message: issues.first { $0.id == "prompt-" + prompt.id }?.message, field: "prompt-" + prompt.id)
                }.padding(20).background(Color.surface, in: RoundedRectangle(cornerRadius: 20)).id("prompt-" + prompt.id)
            }
        }
    }
}
struct PhotoEditor: View {
    @Binding var photos: [ProfilePhoto]
    @State private var items: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var importError: String?
    @State private var cropping: ProfilePhoto?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(photos) { photo in
                        VStack {
                            PhotoView(photo: photo).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 18))
                            Text(photos.first?.id == photo.id ? "Primary photo" : "Photo \((photos.firstIndex { $0.id == photo.id } ?? 0) + 1)").font(.caption)
                            Menu("Edit photo") {
                                Button("Make primary") { move(photo.id, to: 0) }.disabled(photos.first?.id == photo.id)
                                Button("Move earlier") { move(photo.id, to: (photos.firstIndex { $0.id == photo.id } ?? 0) - 1) }.disabled(photos.first?.id == photo.id)
                                Button("Move later") { move(photo.id, to: (photos.firstIndex { $0.id == photo.id } ?? 0) + 1) }.disabled(photos.last?.id == photo.id)
                                Button("Adjust crop") { cropping = photo }
                            }.frame(minHeight: 44).accessibilityLabel("Edit photo \((photos.firstIndex { $0.id == photo.id } ?? 0) + 1)")
                            Button("Remove", role: .destructive) { photos.removeAll { $0.id == photo.id } }.font(.caption).frame(minHeight: 44)
                        }
                    }
                }
            }
            PhotosPicker(selection: $items, maxSelectionCount: max(1, 6 - photos.count), matching: .images) {
                Label("Choose from photo library", systemImage: "photo.badge.plus").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }.disabled(importing || photos.count >= 6).buttonStyle(.bordered)
            if importing { ProgressView("Importing photos…") }
            Text("Or try a fictional demo portrait").font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                ForEach(DemoData.people) { profile in
                    Button {
                        guard let photo = profile.photos.first, photos.count < 6, !photos.contains(where: { $0.id == photo.id }) else { return }
                        photos.append(photo)
                    } label: { Avatar(profile: profile, size: 58) }.buttonStyle(.plain).accessibilityLabel("Use demo portrait \(profile.name)")
                }
            }
            NoteCard(symbol: "lock", text: "Photos stay in memory and are never uploaded. Imported images are resized and stripped of original metadata. AI portraits are for demo use only.")
            if let importError { Text(importError).font(.footnote).foregroundStyle(Color.plum) }
        }.sheet(item: $cropping) { photo in
            PhotoCropEditor(photo: photo) { updated in
                if let index = photos.firstIndex(where: { $0.id == updated.id }) { photos[index] = updated }
            }
        }.task(id: items) {
            guard !items.isEmpty else { return }
            importing = true
            defer { importing = false; items = [] }
            for item in items.prefix(max(0, 6 - photos.count)) {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                          let cleaned = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { throw KindredError.invalid("That image couldn't be opened. Try another photo.") }
                    if !Task.isCancelled { photos.append(.init(id: UUID().uuidString, localData: cleaned, caption: "Your locally selected profile photo")) }
                } catch { importError = error.localizedDescription }
            }
        }
    }
    private func move(_ id: String, to destination: Int) {
        guard let index = photos.firstIndex(where: { $0.id == id }), photos.indices.contains(destination) else { return }
        let photo = photos.remove(at: index)
        photos.insert(photo, at: destination)
    }

}
@MainActor func dismissKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }

struct PhotoCropEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var photo: ProfilePhoto
    let save: (ProfilePhoto) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PhotoView(photo: photo).aspectRatio(0.8, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text("Adjust your framing. Avatars use a square crop of this photo.").font(.subheadline).foregroundStyle(Color.muted)
                    Text("Zoom").font(.headline)
                    Slider(value: $photo.cropZoom, in: 1...3, step: 0.05).accessibilityLabel("Photo zoom")
                    Text("Horizontal position").font(.headline)
                    Slider(value: $photo.cropX, in: -1...1, step: 0.05).accessibilityLabel("Horizontal crop position")
                    Text("Vertical position").font(.headline)
                    Slider(value: $photo.cropY, in: -1...1, step: 0.05).accessibilityLabel("Vertical crop position")
                    Button("Reset crop") { photo.cropZoom = 1; photo.cropX = 0; photo.cropY = 0 }
                }.padding(24)
            }.background(Color.paper).navigationTitle("Adjust crop").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { save(photo); dismiss() } }
                }
        }
    }
}

import SwiftUI

struct BackendAccountView: View {
    enum Mode: String, Identifiable {
        case create, signIn
        var id: String { rawValue }
        var title: String { self == .create ? "Create account" : "Sign in" }
    }

    @State private var mode: Mode
    @State private var awaitingConfirmation = false

    private let onComplete: (String, BackendAccount.Session, BackendAccount.DiscoveryProfile?) -> Void

    init(mode: Mode, onComplete: @escaping (String, BackendAccount.Session, BackendAccount.DiscoveryProfile?) -> Void) {
        self.onComplete = onComplete
        _mode = State(initialValue: mode)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @FocusState private var nameFocused: Bool
    @State private var session: BackendAccount.Session?
    @State private var status: String?
    @State private var busy = false
    private let backend = BackendAccount()

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    privateProfile(session)
                } else {
                    credentialsForm
                }
            }
            .disabled(busy)
            .navigationTitle(session == nil ? "Kindred account" : "Private profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private var credentialsForm: some View {
        Form {
            if awaitingConfirmation {
                Section {
                    Text("Check your email").font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Open the confirmation link sent to \(cleanEmail), then return to Kindred to sign in.")
                    Button("Continue to sign in") {
                        awaitingConfirmation = false
                        mode = .signIn
                    }
                    Button("Use a different email") {
                        awaitingConfirmation = false
                        email = ""
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mode.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(mode == .create ? "Start with your email and a password." : "Welcome back to Kindred.")
                            .foregroundStyle(Color.muted)
                    }.padding(.vertical, 8)
                    TextField("Email address", text: $email).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(mode == .create ? .newPassword : .password)
                    if mode == .create {
                        Text("Use at least 8 characters.").font(.footnote).foregroundStyle(Color.muted)
                    }
                    PrimaryButton(title: mode.title, symbol: "arrow.right") { submit() }
                        .disabled(!validEmail || password.count < (mode == .create ? 8 : 1))
                    Button(mode == .create ? "Already have an account? Sign in" : "New to Kindred? Create account") {
                        mode = mode == .create ? .signIn : .create
                        password = ""
                        status = nil
                    }.frame(minHeight: 44)
                }
            }
            if busy { ProgressView() }
            if let status { Text(status) }
        }
    }

    private func privateProfile(_ session: BackendAccount.Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 10) {
                    Overline(text: "Your Kindred account")
                    Text("What should we call you?")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Add a display name to your private Kindred profile.")
                        .font(.body).foregroundStyle(Color.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display name").font(.headline)
                    TextField("e.g. Alex", text: $displayName)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit { nameFocused = false }
                        .accessibilityLabel("Display name")
                        .padding(16)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(nameFocused ? Color.plum : Color.ink.opacity(0.14))
                                .allowsHitTesting(false)
                        }
                    if cleanDisplayName.count > 60 {
                        Text("Use 60 characters or fewer.")
                            .font(.footnote).foregroundStyle(Color.plum)
                    }
                }

                PrimaryButton(title: busy ? "Saving…" : "Save and continue", symbol: "arrow.right") {
                    let name = cleanDisplayName
                    nameFocused = false
                    perform {
                        try await backend.saveProfile(name: name, session: session)
                        onComplete(name, session, nil)
                    }
                }
                .disabled(cleanDisplayName.isEmpty || cleanDisplayName.count > 60)

                if let status {
                    Text(status).font(.footnote).foregroundStyle(Color.plum)
                }
                Button("Sign out") {
                    nameFocused = false
                    perform {
                        try await backend.signOut(session: session)
                        self.session = nil
                        displayName = ""
                        password = ""
                        mode = .signIn
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
            .foregroundStyle(Color.ink)
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.paper)
        .onChange(of: displayName) { status = nil }
    }

    private var cleanDisplayName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validEmail: Bool {
        let parts = cleanEmail.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !cleanEmail.contains(where: \.isWhitespace)
    }

    private func submit() {
        perform {
            if mode == .create {
                if let signedIn = try await backend.createAccount(email: cleanEmail, password: password) {
                    displayName = ""
                    session = signedIn
                } else {
                    awaitingConfirmation = true
                }
            } else {
                let signedIn = try await backend.signIn(email: cleanEmail, password: password)
                let complete = try await backend.loadDiscoveryProfile(session: signedIn)
                let name: String
                if let complete { name = complete.profile.name }
                else { name = try await backend.loadProfile(session: signedIn) }
                if name.isEmpty {
                    session = signedIn
                } else {
                    onComplete(name, signedIn, complete)
                }
            }
            password = ""
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        status = nil
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { status = error.localizedDescription }
        }
    }
}

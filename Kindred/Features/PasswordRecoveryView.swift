import SwiftUI

struct PasswordRecoveryView: View {
    let link: URL
    let onClose: (UUID?) -> Void

    @State private var session: BackendAccount.Session?
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = true
    @State private var errorMessage: String?
    private let backend = BackendAccount()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose a new password").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    if busy { ProgressView(session == nil ? "Opening reset link…" : "Updating password…") }
                    if let session {
                        SecureField("New password", text: $password).textContentType(.newPassword)
                        SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword)
                        Text("Use at least 8 characters.").font(.footnote).foregroundStyle(Color.muted)
                        if !confirmation.isEmpty && password != confirmation {
                            Text("The passwords don’t match.").font(.footnote).foregroundStyle(Color.plum)
                        }
                        PrimaryButton(title: "Update password") { updatePassword(for: session) }
                            .disabled(password.count < 8 || password != confirmation || busy)
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(Color.plum) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .disabled(busy)
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if let session { Task { try? await backend.signOut(session: session) } }
                        onClose(nil)
                    }.disabled(busy)
                }
            }
            .task {
                do { session = try await backend.exchangePasswordResetLink(link) }
                catch {
                    errorMessage = "This link couldn’t be opened. Request a new password reset link on this device."
                }
                busy = false
            }
        }
    }

    private func updatePassword(for session: BackendAccount.Session) {
        busy = true
        errorMessage = nil
        let newPassword = password
        Task {
            defer { busy = false }
            do {
                try await backend.resetPassword(newPassword, session: session)
                try? await backend.signOut(session: session)
                onClose(session.user.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

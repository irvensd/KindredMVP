import SwiftUI

struct SafetyReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var showsSignOut = false

    @State private var reviewed = false
    @State private var reports: [BackendAccount.SafetyReport] = []
    @State private var offset = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var updating = false
    @State private var error: String?
    @State private var resolving: BackendAccount.SafetyReport?
    @State private var note = ""

    var body: some View {
        List {
            Section {
                Text("Safety review queue")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Claim a report before reviewing it. Record the decision and any action you took before closing it.")
                    .foregroundStyle(Color.muted)
                Picker("Queue", selection: $reviewed) {
                    Text("Open").tag(false)
                    Text("Resolved").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(loading || updating)
            }

            if loading { ProgressView("Loading reports…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(Color.muted)
                    Button("Refresh queue") { Task { await load(reset: true) } }
                        .disabled(loading || updating)
                }
            } else if reports.isEmpty && !loading {
                Text(reviewed ? "No resolved reports" : "No open reports").foregroundStyle(Color.muted)
            }

            ForEach(reports) { report in
                reportSection(report)
            }
            if hasMore {
                Button("Load more reports") { Task { await load(reset: false) } }
                    .disabled(loading || updating)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("Safety review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsSignOut {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        updating = true
                        Task {
                            defer { updating = false }
                            do { try await store.signOutAccount() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(updating)
                }
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await load(reset: true) }
        }
        .onChange(of: reviewed) { _, _ in
            Task { await load(reset: true) }
        }
        .refreshable { await load(reset: true) }
        .sheet(item: $resolving) { report in
            resolutionSheet(report)
        }
    }

    private func reportSection(_ report: BackendAccount.SafetyReport) -> some View {
        Section {
            Text(report.reported_name ?? "Member").font(.headline)
            Text("Member ID: \(report.reported_id.uuidString.lowercased())")
                .font(.caption).foregroundStyle(Color.muted)
                .textSelection(.enabled)
            Text(report.created_at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(Color.muted)
            if !report.details.isEmpty { Text(report.details) }
            if let resolution = report.resolution {
                Text("Resolution").font(.headline)
                Text(resolution)
            } else {
                Text(report.assigned_to_me ? "Assigned to you" : report.assigned ? "Assigned to another reviewer" : "Unassigned")
                    .font(.subheadline).foregroundStyle(Color.muted)
                if report.assigned_to_me {
                    Button("Record resolution") { note = ""; resolving = report }
                    Button("Release report") { Task { await submit(report, action: .release) } }
                } else if !report.assigned {
                    Button("Claim report") { Task { await submit(report, action: .claim) } }
                }
            }
        } header: {
            Text(report.reason)
        }
        .disabled(updating || loading)
    }

    private func resolutionSheet(_ report: BackendAccount.SafetyReport) -> some View {
        NavigationStack {
            Form {
                Text("Save the review outcome and any action you took. This note is visible only to safety reviewers.")
                    .foregroundStyle(Color.muted)
                TextField("Resolution note", text: $note, axis: .vertical).lineLimit(3...8)
                if let error { Text(error).foregroundStyle(Color.plum) }
            }
            .navigationTitle("Resolve report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { resolving = nil }.disabled(updating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Resolve") {
                        let resolution = note.trimmed
                        Task { await submit(report, action: .resolve, note: resolution) }
                    }
                    .disabled(updating || !(1...500).contains(note.trimmed.count))
                }
            }
            .interactiveDismissDisabled(updating)
        }
    }

    private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        error = nil
        if reset {
            reports = []
            offset = 0
            hasMore = false
        }
        defer { loading = false }
        do {
            let page = try await store.loadSafetyReports(reviewed: reviewed, offset: offset)
            guard !Task.isCancelled else { return }
            let existing = Set(reports.map(\.id))
            reports += page.filter { !existing.contains($0.id) }
            offset += page.count
            hasMore = page.count == 30
        } catch {
            if case BackendAccount.RequestError.rejected(403) = error {
                reports = []
                hasMore = false
                self.error = "This account does not have safety review access."
            } else if !Task.isCancelled {
                self.error = error.localizedDescription
            }
        }
    }

    private func submit(_ report: BackendAccount.SafetyReport, action: BackendAccount.SafetyAction, note: String? = nil) async {
        guard !updating, !loading else { return }
        updating = true
        error = nil
        defer { updating = false }
        do {
            try await store.reviewSafetyReport(report.id, action: action, note: note)
            resolving = nil
            await load(reset: true)
        } catch {
            if case BackendAccount.RequestError.rejected(403) = error {
                resolving = nil
                reports = []
                hasMore = false
            }
            self.error = error.localizedDescription
        }
    }
}

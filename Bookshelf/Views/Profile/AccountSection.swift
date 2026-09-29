import SwiftUI

/// "Backup & sync" on the Profile tab.
struct AccountSection: View {
    @Environment(AccountStore.self) private var account
    @State private var showingAuth = false
    @State private var confirmingLogOut = false

    var body: some View {
        if account.isConfigured {
            Section {
                if let email = account.email {
                    LabeledContent("Account", value: email)
                    statusRow
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await account.sync() }
                    }
                    .disabled(account.status == .syncing)
                    Button("Log out", role: .destructive) { confirmingLogOut = true }
                } else {
                    Button("Sign up or log in", systemImage: "person.badge.key") { showingAuth = true }
                }
            } header: {
                Text("Backup & sync")
            } footer: {
                if !account.isSignedIn {
                    Text("Back up your library and keep it in sync across your devices.")
                }
            }
            .sheet(isPresented: $showingAuth) {
                AuthView()
            }
            .confirmationDialog("Log out?", isPresented: $confirmingLogOut, titleVisibility: .visible) {
                Button("Log out", role: .destructive) {
                    Task { await account.logOut() }
                }
            } message: {
                Text("Your library stays on this phone. It just stops syncing until you log in again.")
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch account.status {
        case .syncing:
            HStack {
                Text("Syncing…")
                Spacer()
                ProgressView()
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.footnote)
        case .idle:
            LabeledContent("Last synced") {
                if let lastSynced = account.lastSynced {
                    Text(lastSynced, format: .relative(presentation: .named))
                } else {
                    Text("Not yet")
                }
            }
        }
    }
}

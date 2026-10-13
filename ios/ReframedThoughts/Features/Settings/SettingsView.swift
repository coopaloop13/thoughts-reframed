import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section { NavigationLink("Re-record my voice") { RerecordVoiceView() } }
                Section { Button("Sign out") { app.signOut() } }
                Section {
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                } footer: { Text("Deletes your voice clone, recordings and affirmations. This cannot be undone.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete your account and all recordings?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await deleteAccount() } }
            }
        }
    }

    private func deleteAccount() async {
        do { try await app.api.deleteAccount(); app.signOut() }
        catch {
            self.error = (error as? APIError)?.userMessage ?? error.localizedDescription
            if case APIError.unauthenticated = error { app.signOut() }
        }
    }
}

/// Hosts the enrollment flow from Settings and pops back when the new voice is kept.
private struct RerecordVoiceView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { EnrollVoiceView(isRerecord: true) { _ in dismiss() } }
}

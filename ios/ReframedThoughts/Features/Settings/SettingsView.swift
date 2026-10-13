import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
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
        catch { self.error = (error as? APIError)?.userMessage ?? error.localizedDescription; app.handle(error) }
    }
}

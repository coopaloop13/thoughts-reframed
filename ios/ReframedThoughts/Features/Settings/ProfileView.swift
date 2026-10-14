import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var vm: ProfileViewModel?

    var body: some View {
        Group {
            switch vm?.state {
            case .none, .loading: ProgressView().tint(.forest)
            case .failed(let msg):
                VStack(spacing: Theme.spacing) { Text(msg); Button("Retry") { Task { await vm?.load() } }.buttonStyle(PrimaryButtonStyle()) }.padding(Theme.spacing)
            case .loaded(nil):
                ContentUnavailableView("Nothing yet", systemImage: "book.closed", description: Text("After your first reframe, Reframed keeps short notes here about what it has noticed and what has helped."))
            case .loaded(let notes?):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Reframed's notes").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                        Text(notes).lineSpacing(4)
                        Text("Updated after every session. Deleting your account erases these notes.").font(.footnote).foregroundStyle(Color.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).card().padding(Theme.spacing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sand.ignoresSafeArea())
        .navigationTitle("What Reframed remembers")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm == nil { vm = ProfileViewModel(api: app.api, onUnauthenticated: { app.signOut() }) }; await vm?.load() }
    }
}

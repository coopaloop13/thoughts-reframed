import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var vm: HistoryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                switch vm?.state {
                case .none, .loading: ProgressView().tint(.forest)
                case .failed(let msg):
                    VStack(spacing: Theme.spacing) { Text(msg); Button("Retry") { Task { await vm?.load() } }.buttonStyle(PrimaryButtonStyle()) }.padding(Theme.spacing)
                case .loaded(let sessions):
                    if sessions.isEmpty { ContentUnavailableView("No reframes yet", systemImage: "waveform", description: Text("Your reframed thoughts will collect here.")) }
                    else {
                        List(sessions) { s in
                            NavigationLink(value: s) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(s.reframedText ?? s.transcript ?? "…").font(.display(.body, weight: .regular)).lineLimit(2)
                                    Text("\(s.createdAt, style: .date) · \(s.status.progressLabel)").font(.caption).foregroundStyle(Color.muted)
                                }.padding(.vertical, 4)
                            }
                            .listRowBackground(Color.surface)
                        }
                        .scrollContentBackground(.hidden)
                        .refreshable { await vm?.load() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sand.ignoresSafeArea())
            .task { if vm == nil { vm = HistoryViewModel(api: app.api, onUnauthenticated: { app.signOut() }) }; await vm?.load() }
            .navigationTitle("History")
            .navigationDestination(for: Session.self) { SessionDetailView(session: $0) }
        }
    }
}

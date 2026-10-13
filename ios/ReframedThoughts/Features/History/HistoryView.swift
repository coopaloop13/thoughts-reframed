import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var vm: HistoryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                switch vm?.state {
                case .none, .loading: ProgressView()
                case .failed(let msg): VStack { Text(msg); Button("Retry") { Task { await vm?.load() } } }
                case .loaded(let sessions):
                    if sessions.isEmpty { ContentUnavailableView("No reframes yet", systemImage: "waveform") }
                    else {
                        List(sessions) { s in
                            NavigationLink(value: s) {
                                VStack(alignment: .leading) {
                                    Text(s.reframedText ?? s.transcript ?? "…").lineLimit(2)
                                    Text("\(s.createdAt, style: .date) · \(s.status.progressLabel)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .refreshable { await vm?.load() }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Session.self) { SessionDetailView(session: $0) }
        }
        .task { if vm == nil { vm = HistoryViewModel(api: app.api, onUnauthenticated: { app.signOut() }) }; await vm?.load() }
    }
}

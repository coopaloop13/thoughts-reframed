import SwiftUI

struct SessionDetailView: View {
    @Environment(AppState.self) private var app
    let session: Session
    @State private var vm: RecordFlowViewModel?

    var body: some View {
        Group {
            switch vm?.phase {
            case .none, .idle: ProgressView().tint(.forest)
            case .done(let s): PlaybackView(session: s)
            case .processing(let status): ProcessingView(label: status.progressLabel)
            case .failed(let msg, let crisis):
                VStack(spacing: 12) { if crisis { CrisisCard() }; Text(msg).multilineTextAlignment(.center); if let raw = session.error { Text(raw).font(.caption2).foregroundStyle(Color.muted) } }.padding(Theme.spacing)
            default: ProgressView().tint(.forest)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sand.ignoresSafeArea())
        .navigationTitle(session.createdAt.formatted(date: .abbreviated, time: .shortened))
        .task {
            if vm == nil {
                let m = RecordFlowViewModel(api: app.api, recorder: AudioRecorder().asRecording, onUnauthenticated: { app.signOut() })
                vm = m
                await m.resume(session: session)
            }
        }
    }
}

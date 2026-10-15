import SwiftUI
import UIKit

struct RecordView: View {
    @Environment(AppState.self) private var app
    @State private var recorder = AudioRecorder()
    @State private var vm: RecordFlowViewModel?
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 48

    var body: some View {
        NavigationStack {
            Group { if let vm { content(vm) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sand.ignoresSafeArea())
                .navigationTitle("Reframe")
        }
        .onAppear { if vm == nil { vm = RecordFlowViewModel(api: app.api, recorder: recorder.asRecording, onUnauthenticated: { app.signOut() }) } }
    }

    @ViewBuilder private func content(_ vm: RecordFlowViewModel) -> some View {
        switch vm.phase {
        case .idle:
            VStack(spacing: Theme.spacing) {
                Spacer()
                Text("What's the thought?").font(.display(.title))
                Text("Say it out loud. You'll hear it back, reframed.").foregroundStyle(Color.muted).multilineTextAlignment(.center)
                Spacer()
                Button("Start recording", systemImage: "mic.fill") { Task { await vm.record() } }.buttonStyle(RecordButtonStyle())
                Text("Tap to start").font(.footnote).foregroundStyle(Color.muted)
                Spacer()
            }.padding(Theme.spacing)
        case .recording:
            VStack(spacing: Theme.spacing) {
                Spacer()
                Text("Listening").font(.display(.title))
                Text(String(format: "%.0f s", recorder.duration)).font(.display(countdownSize)).monospacedDigit().foregroundStyle(Color.forest)
                Spacer()
                Button("Stop recording", systemImage: "stop.fill") { Task { await vm.stopAndSubmit() } }.buttonStyle(RecordButtonStyle(active: true))
                Text("Tap when you're done").font(.footnote).foregroundStyle(Color.muted)
                Spacer()
            }.padding(Theme.spacing)
        case .uploading: ProcessingView(label: SessionStatus.uploaded.progressLabel)
        case .processing(let status): ProcessingView(label: status.progressLabel)
        case .done(let session): PlaybackView(session: session, onDone: { vm.reset() })
        case .failed(let msg, let crisis):
            VStack(spacing: Theme.spacing) {
                if crisis { CrisisCard() }
                Text(msg).multilineTextAlignment(.center)
                Button("Try again") { vm.reset() }.buttonStyle(PrimaryButtonStyle())
            }.padding(Theme.spacing)
        case .permissionDenied:
            VStack(spacing: Theme.spacing) {
                Text("Microphone access is off. Enable it in Settings to record.").multilineTextAlignment(.center)
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }.padding(Theme.spacing)
        }
    }
}

import SwiftUI
import UIKit

struct RecordView: View {
    @Environment(AppState.self) private var app
    @State private var recorder = AudioRecorder()
    @State private var vm: RecordFlowViewModel?

    var body: some View {
        NavigationStack {
            Group { if let vm { content(vm) } }
                .navigationTitle("Reframe")
        }
        .onAppear { if vm == nil { vm = RecordFlowViewModel(api: app.api, recorder: recorder.asRecording, onUnauthenticated: { app.signOut() }) } }
    }

    @ViewBuilder private func content(_ vm: RecordFlowViewModel) -> some View {
        switch vm.phase {
        case .idle:
            VStack(spacing: 24) {
                Text("What's the thought?").font(.title2)
                Text("Say it out loud. We'll give it back to you, reframed.").foregroundStyle(.secondary)
                Button { Task { await vm.record() } } label: { Image(systemName: "mic.circle.fill").font(.system(size: 96)) }
            }
        case .recording:
            VStack(spacing: 24) {
                Text(String(format: "%.0f s", recorder.duration)).font(.largeTitle.monospacedDigit())
                Button("Done") { Task { await vm.stopAndSubmit() } }.buttonStyle(.borderedProminent)
            }
        case .uploading: ProcessingView(label: SessionStatus.uploaded.progressLabel)
        case .processing(let status): ProcessingView(label: status.progressLabel)
        case .done(let session): PlaybackView(session: session, onDone: { vm.reset() })
        case .failed(let msg):
            VStack(spacing: 16) { Text(msg).multilineTextAlignment(.center); Button("Try again") { vm.reset() }.buttonStyle(.borderedProminent) }.padding()
        case .permissionDenied:
            VStack(spacing: 16) {
                Text("Microphone access is off. Enable it in Settings to record.").multilineTextAlignment(.center)
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }.padding()
        }
    }
}

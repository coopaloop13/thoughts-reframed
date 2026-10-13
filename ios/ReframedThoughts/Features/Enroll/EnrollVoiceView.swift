import SwiftUI
import UIKit

struct EnrollVoiceView: View {
    /// Re-record mode: a different title, and completion goes to `onDone` instead of the app's enroll route.
    var isRerecord = false
    var onDone: ((User) -> Void)? = nil

    @Environment(AppState.self) private var app
    @State private var recorder = AudioRecorder()
    @State private var player = AudioPlayer()
    @State private var vm: EnrollVoiceViewModel?

    var body: some View {
        VStack(spacing: 20) {
            Text(isRerecord ? "Re-record your voice" : "Set up your voice").font(.title2.bold())
            Text("Read this paragraph aloud:").foregroundStyle(.secondary)
            Text(EnrollVoiceViewModel.referenceText).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Spacer()
            if let vm { content(vm) }
        }
        .padding()
        .onAppear { if vm == nil { vm = EnrollVoiceViewModel(api: app.api, recorder: recorder.asRecording) } }
        .onChange(of: vm?.phase) { _, phase in
            switch phase {
            case .done(let user): (onDone ?? app.didEnroll)(user)
            case .preview(let url, _): player.play(url)
            default: break
            }
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder private func content(_ vm: EnrollVoiceViewModel) -> some View {
        switch vm.phase {
        case .idle: Button("Start recording") { Task { await vm.record() } }.buttonStyle(.borderedProminent)
        case .recording:
            Text(String(format: "%.0f s", recorder.duration)).monospacedDigit()
            Button("Stop") { vm.stop() }.buttonStyle(.borderedProminent).tint(.red)
        case .review:
            Button("Use this recording") { Task { await vm.upload() } }.buttonStyle(.borderedProminent)
            Button("Record again") { vm.retake() }
        case .uploading: ProgressView("Cloning your voice…")
        case .preview(let url, _):
            Text("Does this sound like you?").font(.headline)
            Button { player.isPlaying ? player.stop() : player.play(url) } label: {
                Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 56))
            }
            Button("Keep this voice") { player.stop(); vm.keep() }.buttonStyle(.borderedProminent)
            Button("Record again") { player.stop(); vm.retake() }
        case .done: ProgressView()
        case .failed(let msg):
            Text(msg).foregroundStyle(.red).multilineTextAlignment(.center)
            Button("Try again") { vm.retake() }
        case .permissionDenied:
            Text("Microphone access is off. Enable it in Settings to continue.").multilineTextAlignment(.center)
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
        }
    }
}

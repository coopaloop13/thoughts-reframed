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
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Text(isRerecord ? "Re-record your voice" : "Set up your voice").font(.display(30))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Read this aloud, naturally, like you're talking to a friend.").foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(EnrollVoiceViewModel.referenceText).font(.display(20, weight: .regular)).lineSpacing(6).card()
                if let vm { content(vm) }
            }
            .padding(Theme.spacing)
        }
        .background(Color.sand.ignoresSafeArea())
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
        case .idle: Button("Start recording") { Task { await vm.record() } }.buttonStyle(PrimaryButtonStyle())
        case .recording:
            Text(String(format: "%.0f s", recorder.duration)).font(.display(40)).monospacedDigit()
            Button { vm.stop() } label: { Image(systemName: "stop.fill") }.buttonStyle(RecordButtonStyle(active: true))
            Text("Tap to stop when you've finished the paragraph.").font(.footnote).foregroundStyle(Color.muted)
        case .review:
            Button("Use this recording") { Task { await vm.upload() } }.buttonStyle(PrimaryButtonStyle())
            Button("Record again") { vm.retake() }.buttonStyle(SecondaryButtonStyle())
        case .uploading: ProcessingView(label: "Cloning your voice…")
        case .preview(let url, _):
            Text("Does this sound like you?").font(.display(22))
            Button { player.isPlaying ? player.stop() : player.play(url) } label: {
                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
            }.buttonStyle(RecordButtonStyle(active: true))
            Button("Keep this voice") { player.stop(); vm.keep() }.buttonStyle(PrimaryButtonStyle())
            Button("Record again") { player.stop(); vm.retake() }.buttonStyle(SecondaryButtonStyle())
        case .done: ProgressView()
        case .failed(let msg):
            Text(msg).foregroundStyle(Color.clay).multilineTextAlignment(.center)
            Button("Try again") { vm.retake() }.buttonStyle(PrimaryButtonStyle())
        case .permissionDenied:
            Text("Microphone access is off. Enable it in Settings to continue.").multilineTextAlignment(.center)
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
        }
    }
}

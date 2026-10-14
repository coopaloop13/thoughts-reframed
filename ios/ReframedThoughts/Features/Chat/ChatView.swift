import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(AppState.self) private var app
    let session: Session
    var onTurnsChanged: (([Turn]) -> Void)? = nil
    @State private var recorder = AudioRecorder()
    @State private var player = AudioPlayer()
    @State private var vm: ChatViewModel?

    var body: some View {
        Group { if let vm { content(vm) } else { ProgressView().tint(.forest) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sand.ignoresSafeArea())
            .navigationTitle("Work through it")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if vm == nil {
                    let m = ChatViewModel(session: session, api: app.api, recorder: recorder.asRecording, onUnauthenticated: { app.signOut() })
                    m.onReplyReady = { player.play($0) }
                    vm = m
                }
            }
            .onDisappear { player.stop() }
    }

    @ViewBuilder private func content(_ vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacing) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You said").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                            Text(vm.session.transcript ?? "").italic().foregroundStyle(Color.muted)
                            Text(vm.session.reframedText ?? "").font(.display(20, weight: .medium)).padding(.top, 4)
                        }.frame(maxWidth: .infinity, alignment: .leading).card()
                        if vm.showsCrisis { CrisisCard() }
                        ForEach(vm.turns) { t in
                            if let u = t.userText { bubble(u, mine: true) }
                            if let a = t.agentText { agentBubble(a, audio: t.audioUrl) } else if !t.status.isTerminal { Text(t.status.chatLabel).font(.footnote).foregroundStyle(Color.muted) }
                        }
                        if vm.isClosed { Text("Done for now. Come back any time.").font(.footnote).foregroundStyle(Color.muted).frame(maxWidth: .infinity) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(Theme.spacing)
                }
                .onChange(of: vm.turns) { onTurnsChanged?(vm.turns); withAnimation { proxy.scrollTo("bottom") } }
            }
            controls(vm)
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(text).foregroundStyle(mine ? Color.onClay : Color.bark).padding(12)
            .background(mine ? Color.clay : Color.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
    private func agentBubble(_ text: String, audio: URL?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            bubble(text, mine: false)
            if let audio { Button { player.isPlaying ? player.stop() : player.play(audio) } label: { Image(systemName: player.isPlaying ? "stop.circle" : "play.circle").font(.title2) }.tint(.forest).accessibilityLabel(player.isPlaying ? "Stop reply" : "Play reply") }
        }
    }

    @ViewBuilder private func controls(_ vm: ChatViewModel) -> some View {
        VStack(spacing: 8) {
            switch vm.phase {
            case .idle where vm.isClosed: EmptyView()
            case .idle:
                Button { Task { await vm.record() } } label: { Image(systemName: "mic.fill") }.buttonStyle(RecordButtonStyle()).accessibilityLabel("Reply by voice")
                Text("Tap to reply").font(.footnote).foregroundStyle(Color.muted)
            case .recording:
                Button { Task { await vm.stopAndSend() } } label: { Image(systemName: "stop.fill") }.buttonStyle(RecordButtonStyle(active: true)).accessibilityLabel("Stop and send")
                Text(String(format: "%.0f s · tap when you're done", recorder.duration)).font(.footnote).foregroundStyle(Color.muted)
            case .sending: ProgressView().tint(.forest); Text(SessionStatus.uploaded.chatLabel).font(.footnote).foregroundStyle(Color.muted)
            case .processing(let s): ProgressView().tint(.forest); Text(s.chatLabel).font(.footnote).foregroundStyle(Color.muted)
            case .failed(let msg):
                Text(msg).multilineTextAlignment(.center).font(.footnote)
                Button("Try again") { vm.dismissError() }.buttonStyle(SecondaryButtonStyle())
            case .permissionDenied:
                Text("Microphone access is off. Enable it in Settings to reply.").font(.footnote).multilineTextAlignment(.center)
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity)
        .background(Color.sand)
    }
}

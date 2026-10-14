import SwiftUI

struct PlaybackView: View {
    let session: Session
    var onDone: (() -> Void)? = nil
    @State private var player = AudioPlayer()
    @State private var showChat = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.crisis ? "A note for you" : "Reframed").font(.caption.weight(.semibold)).foregroundStyle(Color.forest).textCase(.uppercase)
                    Text(session.reframedText ?? "").font(.display(26, weight: .medium)).lineSpacing(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()
                if session.crisis { CrisisCard() }
                if let url = session.audioUrl {
                    Button { player.isPlaying ? player.stop() : player.play(url) } label: {
                        Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                    }.buttonStyle(RecordButtonStyle(active: true))
                    Text(player.isPlaying ? "Playing in your voice" : "Play again").font(.footnote).foregroundStyle(Color.muted)
                }
                if let t = session.transcript {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You said").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                        Text(t).italic().foregroundStyle(Color.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !session.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Worked through").font(.caption.weight(.semibold)).foregroundStyle(Color.muted).textCase(.uppercase)
                        ForEach(session.turns) { t in
                            if let u = t.userText { Text(u).italic().foregroundStyle(Color.muted) }
                            if let a = t.agentText { Text(a) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                }
                Button(session.turns.isEmpty ? "Work through this" : "Continue") { showChat = true }.buttonStyle(SecondaryButtonStyle())
                if let onDone { Button("New thought", action: onDone).buttonStyle(PrimaryButtonStyle()) }
            }
            .padding(Theme.spacing)
        }
        .background(Color.sand.ignoresSafeArea())
        .navigationDestination(isPresented: $showChat) { ChatView(session: session) }
        .onAppear { if let url = session.audioUrl { player.play(url) } }
        .onDisappear { player.stop() }
    }
}

import SwiftUI

struct PlaybackView: View {
    let session: Session
    var onDone: (() -> Void)? = nil
    @State private var player = AudioPlayer()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reframed").font(.caption.weight(.semibold)).foregroundStyle(Color.forest).textCase(.uppercase)
                    Text(session.reframedText ?? "").font(.display(26, weight: .medium)).lineSpacing(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()
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
                if let onDone { Button("New thought", action: onDone).buttonStyle(PrimaryButtonStyle()) }
            }
            .padding(Theme.spacing)
        }
        .background(Color.sand.ignoresSafeArea())
        .onAppear { if let url = session.audioUrl { player.play(url) } }
        .onDisappear { player.stop() }
    }
}

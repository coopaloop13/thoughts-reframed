import SwiftUI

struct PlaybackView: View {
    let session: Session
    var onDone: (() -> Void)? = nil
    @State private var player = AudioPlayer()

    var body: some View {
        VStack(spacing: 24) {
            if let t = session.transcript { Text("You said").font(.caption).foregroundStyle(.secondary); Text(t).italic() }
            Divider()
            Text("Reframed").font(.caption).foregroundStyle(.secondary)
            Text(session.reframedText ?? "").font(.title3).multilineTextAlignment(.center)
            if let url = session.audioUrl {
                Button { player.isPlaying ? player.stop() : player.play(url) } label: {
                    Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 72))
                }
            }
            if let onDone { Button("New thought", action: onDone) }
        }
        .padding()
        .onAppear { if let url = session.audioUrl { player.play(url) } }
        .onDisappear { player.stop() }
    }
}

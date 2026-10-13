import AVFoundation
import Observation

@MainActor @Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private var player: AVPlayer?
    private var observer: Any?

    func play(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in Task { @MainActor in self?.isPlaying = false } }
        player?.play(); isPlaying = true
    }
    func stop() { player?.pause(); isPlaying = false }
}

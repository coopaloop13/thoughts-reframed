import AVFoundation
import Observation

/// Struct-of-closures so ViewModels can be tested without AVFoundation.
struct Recording {
    var requestPermission: @MainActor () async -> AudioRecorder.Permission
    var start: @MainActor () throws -> Void
    var stop: @MainActor () -> URL?
    var duration: @MainActor () -> TimeInterval
}

@MainActor @Observable
final class AudioRecorder {
    enum Permission { case undetermined, granted, denied }
    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?

    func requestPermission() async -> Permission {
        await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        let file = FileManager.default.temporaryDirectory.appending(path: "recording_\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100.0, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        recorder = try AVAudioRecorder(url: file, settings: settings)
        recorder?.record()
        url = file; isRecording = true; duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.duration += 0.1 } }
    }

    func stop() -> URL? {
        recorder?.stop(); timer?.invalidate(); timer = nil; isRecording = false
        return url
    }

    var asRecording: Recording {
        Recording(requestPermission: { await self.requestPermission() }, start: { try self.start() }, stop: { self.stop() }, duration: { self.duration })
    }
}

import Foundation
import Observation

@MainActor @Observable
final class EnrollVoiceViewModel {
    enum Phase: Equatable { case idle, recording, review(URL), uploading, preview(URL, User), done(User), failed(String), permissionDenied }
    static let minimumSeconds: TimeInterval = 8
    /// VoiceStudio (OmniVoice) ignores our transcript for references over 20s and tries to auto-transcribe
    /// them with a Whisper model that isn't installed, which breaks every later synthesis. Keep takes under it.
    static let maximumSeconds: TimeInterval = 20
    /// ~50 words: reads in 13-17s, under `maximumSeconds` with room for slow readers.
    static let referenceText = """
    Hi, this is my voice, and I'm recording it so the app can learn how I sound. \
    Have you noticed how one difficult thought can color a whole afternoon? \
    Some days I'm hard on myself, and that hurts! \
    But I can pause, breathe, and choose a kinder way to say it.
    """

    private(set) var phase: Phase = .idle
    private let api: API
    private let recorder: Recording
    /// Auto-stop lands at 19.5s, not 20: a timer firing at exactly 20 plus the encoder tail gives a 20.05s
    /// file, and VoiceStudio's check is strictly "over 20".
    private let autoStopAfter: TimeInterval
    private var autoStop: Task<Void, Never>?
    private var fileURL: URL?

    init(api: API, recorder: Recording, autoStopAfter: TimeInterval = EnrollVoiceViewModel.maximumSeconds - 0.5) {
        self.api = api; self.recorder = recorder; self.autoStopAfter = autoStopAfter
    }

    func record() async {
        guard await recorder.requestPermission() == .granted else { phase = .permissionDenied; return }
        do { try recorder.start(); phase = .recording } catch { phase = .failed(error.localizedDescription); return }
        autoStop = Task { [weak self, autoStopAfter] in
            try? await Task.sleep(for: .seconds(autoStopAfter))
            guard let self, !Task.isCancelled, phase == .recording else { return }
            stop()
        }
    }

    func stop() {
        autoStop?.cancel(); autoStop = nil
        let duration = recorder.duration()
        guard let url = recorder.stop() else { phase = .failed("Recording failed."); return }
        guard duration >= Self.minimumSeconds else { try? FileManager.default.removeItem(at: url); phase = .failed("Please read the whole paragraph (at least 8 seconds)."); return }
        guard duration <= Self.maximumSeconds else { try? FileManager.default.removeItem(at: url); phase = .failed("Please keep it under 20 seconds and read at a natural pace."); return }
        fileURL = url; phase = .review(url)
    }

    func upload() async {
        guard let fileURL else { return }
        phase = .uploading
        let user: User
        do { user = try await api.enrollVoice(fileURL, Self.referenceText); try? FileManager.default.removeItem(at: fileURL) }
        catch { phase = .failed((error as? APIError)?.userMessage ?? error.localizedDescription); return }
        // A failed preview never blocks enrollment: the voice is already saved.
        if let url = try? await api.previewVoice() { phase = .preview(url, user) } else { phase = .done(user) }
    }

    func keep() { if case .preview(_, let user) = phase { phase = .done(user) } }

    func retake() { if let fileURL { try? FileManager.default.removeItem(at: fileURL) }; fileURL = nil; phase = .idle }
}

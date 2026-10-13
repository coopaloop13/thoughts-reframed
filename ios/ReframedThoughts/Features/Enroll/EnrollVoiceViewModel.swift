import Foundation
import Observation

@MainActor @Observable
final class EnrollVoiceViewModel {
    enum Phase: Equatable { case idle, recording, review(URL), uploading, preview(URL, User), done(User), failed(String), permissionDenied }
    static let minimumSeconds: TimeInterval = 8
    static let referenceText = """
    Hi, this is my voice, and I'm recording it so the app can learn how I sound when I speak. \
    Have you ever noticed how one difficult thought can color a whole afternoon? \
    Some days I'm hard on myself, and that really hurts! \
    But I can pause, take a breath, and choose a kinder way to say it to myself... one small moment at a time.
    """

    private(set) var phase: Phase = .idle
    private let api: API
    private let recorder: Recording
    private var fileURL: URL?

    init(api: API, recorder: Recording) { self.api = api; self.recorder = recorder }

    func record() async {
        guard await recorder.requestPermission() == .granted else { phase = .permissionDenied; return }
        do { try recorder.start(); phase = .recording } catch { phase = .failed(error.localizedDescription) }
    }

    func stop() {
        let duration = recorder.duration()
        guard let url = recorder.stop() else { phase = .failed("Recording failed."); return }
        guard duration >= Self.minimumSeconds else { try? FileManager.default.removeItem(at: url); phase = .failed("Please read the whole paragraph (at least 8 seconds)."); return }
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

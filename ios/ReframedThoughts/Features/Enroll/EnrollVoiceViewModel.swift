import Foundation
import Observation

@MainActor @Observable
final class EnrollVoiceViewModel {
    enum Phase: Equatable { case idle, recording, review(URL), uploading, done(User), failed(String), permissionDenied }
    static let minimumSeconds: TimeInterval = 8
    static let referenceText = """
    I am speaking in my own voice so this app can learn how I sound. Some days are harder than others, and that is okay. \
    I can notice a difficult thought, take a breath, and choose a kinder way to say it to myself. \
    I am allowed to make mistakes, to rest, and to try again tomorrow.
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
        guard duration >= Self.minimumSeconds else { phase = .failed("Please read the whole paragraph (at least 8 seconds)."); return }
        fileURL = url; phase = .review(url)
    }

    func upload() async {
        guard let fileURL else { return }
        phase = .uploading
        do { phase = .done(try await api.enrollVoice(fileURL, Self.referenceText)) }
        catch { phase = .failed((error as? APIError)?.userMessage ?? error.localizedDescription) }
    }

    func retake() { fileURL = nil; phase = .idle }
}

import Foundation
import Observation

extension SessionStatus {
    var progressLabel: String {
        switch self {
        case .uploaded: "Uploading…"
        case .transcribing: "Listening…"
        case .reframing: "Reframing…"
        case .synthesizing: "Finding your voice…"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }
}

@MainActor @Observable
final class RecordFlowViewModel {
    enum Phase: Equatable { case idle, recording, uploading, processing(SessionStatus), done(Session), failed(String), permissionDenied }
    private(set) var phase: Phase = .idle
    private let api: API
    private let recorder: Recording
    private let onUnauthenticated: () -> Void
    private var watchTask: Task<Void, Never>?

    init(api: API, recorder: Recording, onUnauthenticated: @escaping () -> Void) {
        self.api = api; self.recorder = recorder; self.onUnauthenticated = onUnauthenticated
    }

    func record() async {
        guard phase == .idle else { return }
        guard await recorder.requestPermission() == .granted else { phase = .permissionDenied; return }
        do { try recorder.start(); phase = .recording } catch { phase = .failed(error.localizedDescription) }
    }

    func stopAndSubmit() async {
        guard phase == .recording else { return }
        guard let url = recorder.stop() else { phase = .failed("Recording failed."); return }
        phase = .uploading
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let session = try await api.createSession(url)
            await startFollowing(session.id)
        } catch { fail(error) }
    }

    func resume(session: Session) async {
        if session.status.isTerminal { phase = session.status == .completed ? .done(session) : .failed(Self.failureMessage(session.error)); return }
        phase = .processing(session.status)
        await startFollowing(session.id)
    }

    func reset() { watchTask?.cancel(); watchTask = nil; phase = .idle }

    private func startFollowing(_ id: String) async {
        watchTask?.cancel()
        let t = Task { await self.follow(id) }
        watchTask = t
        await withTaskCancellationHandler { await t.value } onCancel: { t.cancel() }
    }

    private func follow(_ id: String) async {
        do {
            for try await s in api.watchSession(id) {
                guard !Task.isCancelled else { return }
                switch s.status {
                case .completed: phase = .done(s); return
                case .failed: phase = .failed(Self.failureMessage(s.error)); return
                default: phase = .processing(s.status)
                }
            }
            guard !Task.isCancelled else { return }
            phase = .failed(APIError.lostConnection)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        if case APIError.unauthenticated = error { onUnauthenticated(); return }
        phase = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
    }

    static func failureMessage(_ raw: String?) -> String { "Something went wrong while reframing. Please try again." }
}

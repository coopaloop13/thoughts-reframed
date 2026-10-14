import Foundation
import Observation

@MainActor @Observable
final class ChatViewModel {
    enum Phase: Equatable { case idle, recording, sending, processing(SessionStatus), failed(String), permissionDenied }
    private(set) var session: Session
    private(set) var turns: [Turn]
    private(set) var phase: Phase = .idle
    /// The view plays the agent's reply audio when a turn completes.
    var onReplyReady: ((URL) -> Void)?
    private let api: API
    private let recorder: Recording
    private let onUnauthenticated: () -> Void

    var isClosed: Bool { turns.last?.closing == true }
    var showsCrisis: Bool { session.crisis || turns.contains { $0.crisis } }
    var canRecord: Bool { phase == .idle && !isClosed }

    init(session: Session, api: API, recorder: Recording, onUnauthenticated: @escaping () -> Void) {
        self.session = session; self.turns = session.turns; self.api = api; self.recorder = recorder; self.onUnauthenticated = onUnauthenticated
    }

    func record() async {
        guard canRecord else { return }
        guard await recorder.requestPermission() == .granted else { phase = .permissionDenied; return }
        do { try recorder.start(); phase = .recording } catch { phase = .failed(error.localizedDescription) }
    }

    func stopAndSend() async {
        guard phase == .recording else { return }
        guard let url = recorder.stop() else { phase = .failed("Recording failed."); return }
        phase = .sending
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let turn = try await api.sendTurn(session.id, url)
            upsert(turn)
            await follow(turn.id)
        } catch { fail(error) }
    }

    func dismissError() { phase = .idle }

    private func follow(_ id: String) async {
        do {
            for try await t in api.watchTurn(id) {
                guard !Task.isCancelled else { return }
                upsert(t)
                switch t.status {
                case .completed:
                    phase = .idle
                    if let url = t.audioUrl { onReplyReady?(url) }
                    return
                case .failed: phase = .failed(Self.failureMessage); return
                default: phase = .processing(t.status)
                }
            }
            guard !Task.isCancelled else { return }
            phase = .failed(APIError.lostConnection)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func upsert(_ t: Turn) {
        if let i = turns.firstIndex(where: { $0.id == t.id }) { turns[i] = t } else { turns.append(t) }
    }

    private func fail(_ error: Error) {
        if case APIError.unauthenticated = error { onUnauthenticated(); return }
        phase = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
    }

    static let failureMessage = "I didn't catch that. Try saying it again."
}

extension SessionStatus {
    var chatLabel: String {
        switch self {
        case .uploaded: "Sending…"
        case .transcribing: "Listening…"
        case .reframing: "Thinking…"
        case .synthesizing: "Finding your voice…"
        case .completed: "Done"
        case .failed: "Failed"
        }
    }
}

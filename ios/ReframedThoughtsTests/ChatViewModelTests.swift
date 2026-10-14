import Testing
import Foundation
@testable import ReframedThoughts

@MainActor
struct ChatViewModelTests {
    func recording(permission: AudioRecorder.Permission = .granted) -> Recording {
        Recording(requestPermission: { permission }, start: {}, stop: { URL(fileURLWithPath: "/tmp/t.m4a") }, duration: { 2 })
    }
    nonisolated static func stream(_ turns: [Turn], thenThrow error: Error? = nil) -> AsyncThrowingStream<Turn, Error> {
        AsyncThrowingStream { c in turns.forEach { c.yield($0) }; if let error { c.finish(throwing: error) } else { c.finish() } }
    }
    let session = Session.fixture(id: "s1", status: .completed, reframedText: "I am learning")

    @Test func sendsTurnFollowsToCompletedAndPlaysReply() async {
        let done = Turn.fixture(status: .completed, agentText: "What went wrong?", audioUrl: URL(string: "https://r2/t.mp3"))
        let sent = Captured<String?>(nil)
        let api = API.stub(
            sendTurn: { id, _ in sent.value = id; return .fixture(status: .uploaded) },
            watchTurn: { _ in Self.stream([.fixture(status: .transcribing), .fixture(status: .reframing), done]) })
        let vm = ChatViewModel(session: session, api: api, recorder: recording(), onUnauthenticated: {})
        let played = Captured<URL?>(nil)
        vm.onReplyReady = { played.value = $0 }
        await vm.record(); await vm.stopAndSend()
        #expect(sent.value == "s1")
        #expect(vm.turns == [done])
        #expect(vm.phase == .idle)
        #expect(played.value == done.audioUrl)
        #expect(!vm.isClosed && !vm.showsCrisis && vm.canRecord)
    }
    @Test func closingTurnDisablesRecording() async {
        let done = Turn.fixture(status: .completed, agentText: "Take care.", closing: true)
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([done]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.isClosed && !vm.canRecord)
        await vm.record()
        #expect(vm.phase == .idle)
    }
    @Test func crisisFromSessionOrTurnShowsCard() async {
        let crisisSession = Session.fixture(id: "s2", status: .completed, reframedText: "You deserve support.", crisis: true)
        #expect(ChatViewModel(session: crisisSession, api: .stub(), recorder: recording(), onUnauthenticated: {}).showsCrisis)
        let done = Turn.fixture(status: .completed, agentText: "Please reach out.", crisis: true)
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([done]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.showsCrisis)
        #expect(vm.canRecord)
    }
    @Test func startsWithExistingTurns() {
        let old = Turn.fixture(id: "old", status: .completed, agentText: "earlier")
        let s = Session.fixture(id: "s3", status: .completed, turns: [old])
        let vm = ChatViewModel(session: s, api: .stub(), recorder: recording(), onUnauthenticated: {})
        #expect(vm.turns == [old])
    }
    @Test func failedTurnShowsMessageAndCanRetry() async {
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([.fixture(status: .failed, error: "EMPTY_TRANSCRIPT")]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.phase == .failed(ChatViewModel.failureMessage))
        vm.dismissError()
        #expect(vm.canRecord)
    }
    @Test func serverErrorUsesUserMessage() async {
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in throw APIError.server("The previous reply is still on its way") }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.phase == .failed("The previous reply is still on its way"))
    }
    @Test func unauthenticatedCallsBack() async {
        let called = Captured(false)
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in throw APIError.unauthenticated }), recorder: recording(), onUnauthenticated: { called.value = true })
        await vm.record(); await vm.stopAndSend()
        #expect(called.value)
    }
    @Test func permissionDenied() async {
        let vm = ChatViewModel(session: session, api: .stub(), recorder: recording(permission: .denied), onUnauthenticated: {})
        await vm.record()
        #expect(vm.phase == .permissionDenied)
    }
    @Test func streamEndingEarlyFails() async {
        let vm = ChatViewModel(session: session, api: .stub(sendTurn: { _, _ in .fixture() }, watchTurn: { _ in Self.stream([]) }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSend()
        #expect(vm.phase == .failed(APIError.lostConnection))
    }
}

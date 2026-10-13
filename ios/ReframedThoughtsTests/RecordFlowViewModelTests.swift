import Testing
import Foundation
@testable import ReframedThoughts

@MainActor
struct RecordFlowViewModelTests {
    func recording(permission: AudioRecorder.Permission = .granted) -> Recording {
        Recording(requestPermission: { permission }, start: {}, stop: { URL(fileURLWithPath: "/tmp/r.m4a") }, duration: { 4 })
    }
    nonisolated static func stream(_ sessions: [Session], thenThrow error: Error? = nil) -> AsyncThrowingStream<Session, Error> {
        AsyncThrowingStream { c in sessions.forEach { c.yield($0) }; if let error { c.finish(throwing: error) } else { c.finish() } }
    }

    @Test func happyPathFollowsStatusesToDone() async {
        let done = Session.fixture(status: .completed, reframedText: "I am learning", audioUrl: URL(string: "https://r2/a.mp3"))
        let api = API.stub(
            createSession: { _ in .fixture(status: .uploaded) },
            watchSession: { _ in Self.stream([.fixture(status: .uploaded), .fixture(status: .transcribing), .fixture(status: .synthesizing), done]) })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSubmit()
        #expect(vm.phase == .done(done))
    }
    @Test func failedStatusShowsError() async {
        let api = API.stub(createSession: { _ in .fixture() }, watchSession: { _ in Self.stream([.fixture(status: .failed, error: "OpenAI: 500")]) })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSubmit()
        #expect(vm.phase == .failed("Something went wrong while reframing. Please try again."))
    }
    @Test func voiceNotEnrolledSurfacesMessage() async {
        let vm = RecordFlowViewModel(api: .stub(createSession: { _ in throw APIError.voiceNotEnrolled }), recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSubmit()
        #expect(vm.phase == .failed("Set up your voice first."))
    }
    @Test func unauthenticatedCallsBack() async {
        let called = Captured(false)
        let vm = RecordFlowViewModel(api: .stub(createSession: { _ in throw APIError.unauthenticated }), recorder: recording(), onUnauthenticated: { called.value = true })
        await vm.record(); await vm.stopAndSubmit()
        #expect(called.value)
    }
    @Test func streamErrorIsReported() async {
        let api = API.stub(createSession: { _ in .fixture() }, watchSession: { _ in Self.stream([], thenThrow: APIError.transport("socket closed")) })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSubmit()
        #expect(vm.phase == .failed("socket closed"))
    }
    @Test func resumeNonTerminalSessionSubscribes() async {
        let done = Session.fixture(id: "old", status: .completed, reframedText: "ok", audioUrl: URL(string: "https://r2/b.mp3"))
        let watched = Captured<String?>(nil)
        let api = API.stub(watchSession: { id in watched.value = id; return Self.stream([.fixture(id: "old", status: .reframing), done]) })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        await vm.resume(session: .fixture(id: "old", status: .reframing))
        #expect(watched.value == "old")
        #expect(vm.phase == .done(done))
    }
    @Test func resumeTerminalSessionSkipsSubscription() async {
        let done = Session.fixture(id: "old", status: .completed, reframedText: "ok")
        let watched = Captured(false)
        let vm = RecordFlowViewModel(api: .stub(watchSession: { _ in watched.value = true; return Self.stream([]) }), recorder: recording(), onUnauthenticated: {})
        await vm.resume(session: done)
        #expect(!watched.value)
        #expect(vm.phase == .done(done))
    }
    @Test func permissionDenied() async {
        let vm = RecordFlowViewModel(api: .stub(), recorder: recording(permission: .denied), onUnauthenticated: {})
        await vm.record()
        #expect(vm.phase == .permissionDenied)
    }
    @Test func streamEndingBeforeAnyEventFails() async {
        let api = API.stub(createSession: { _ in .fixture() }, watchSession: { _ in Self.stream([]) })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        await vm.record(); await vm.stopAndSubmit()
        #expect(vm.phase == .failed("Lost connection before the affirmation was ready. Check History."))
    }
    @Test func resetCancelsRunningFollow() async {
        let cont = Captured<AsyncThrowingStream<Session, Error>.Continuation?>(nil)
        let api = API.stub(watchSession: { _ in AsyncThrowingStream { cont.value = $0 } })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        let task = Task { await vm.resume(session: .fixture(status: .reframing)) }
        while cont.value == nil { await Task.yield() }
        vm.reset()
        await task.value
        cont.value?.yield(.fixture(status: .completed, reframedText: "late"))
        await Task.yield()
        #expect(vm.phase == .idle)
    }
    @Test func callerCancellationStopsFollow() async {
        let cont = Captured<AsyncThrowingStream<Session, Error>.Continuation?>(nil)
        let terminated = Captured(false)
        let api = API.stub(watchSession: { _ in AsyncThrowingStream { c in
            c.onTermination = { _ in terminated.value = true }
            cont.value = c
        } })
        let vm = RecordFlowViewModel(api: api, recorder: recording(), onUnauthenticated: {})
        let outer = Task { await vm.resume(session: .fixture(status: .reframing)) }
        while cont.value == nil { await Task.yield() }
        outer.cancel()
        await outer.value
        #expect(terminated.value)
    }
}

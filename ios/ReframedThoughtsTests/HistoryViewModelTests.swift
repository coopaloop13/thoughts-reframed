import Testing
import Foundation
@testable import ReframedThoughts

@MainActor
struct HistoryViewModelTests {
    @Test func loadsSessions() async {
        let list = [Session.fixture(id: "a", createdAt: Date(timeIntervalSince1970: 2)), .fixture(id: "b", createdAt: Date(timeIntervalSince1970: 1))]
        let vm = HistoryViewModel(api: .stub(sessions: { list }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .loaded(list))
    }
    @Test func failureShowsMessage() async {
        let vm = HistoryViewModel(api: .stub(sessions: { throw APIError.transport("offline") }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .failed("offline"))
    }
    @Test func unauthenticatedCallsBack() async {
        let called = Captured(false)
        let vm = HistoryViewModel(api: .stub(sessions: { throw APIError.unauthenticated }), onUnauthenticated: { called.value = true })
        await vm.load()
        #expect(called.value)
    }
}

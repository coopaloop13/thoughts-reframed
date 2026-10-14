import Testing
@testable import ReframedThoughts

@MainActor
struct ProfileViewModelTests {
    @Test func loadsProfile() async {
        let vm = ProfileViewModel(api: .stub(me: { User(id: "u", hasVoice: true, profile: "Tends to catastrophize.") }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .loaded("Tends to catastrophize."))
    }
    @Test func emptyProfileIsNil() async {
        let vm = ProfileViewModel(api: .stub(me: { User(id: "u", hasVoice: true) }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .loaded(nil))
    }
    @Test func failureShowsMessage() async {
        let vm = ProfileViewModel(api: .stub(me: { throw APIError.transport("offline") }), onUnauthenticated: {})
        await vm.load()
        #expect(vm.state == .failed("offline"))
    }
    @Test func unauthenticatedCallsBack() async {
        let called = Captured(false)
        let vm = ProfileViewModel(api: .stub(me: { throw APIError.unauthenticated }), onUnauthenticated: { called.value = true })
        await vm.load()
        #expect(called.value)
    }
}

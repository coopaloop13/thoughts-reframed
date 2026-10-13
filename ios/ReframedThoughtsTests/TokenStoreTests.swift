import Testing
@testable import ReframedThoughts

struct TokenStoreTests {
    @Test func roundTrip() throws {
        let store = TokenStore(service: "com.coopertech.reframedthoughts.tests")
        store.clear()
        #expect(store.read() == nil)
        try store.write("tok-1")
        #expect(store.read() == "tok-1")
        try store.write("tok-2")
        #expect(store.read() == "tok-2")
        store.clear()
        #expect(store.read() == nil)
    }
}

import Testing
import Foundation
@testable import ReframedThoughts

@MainActor @Suite(.serialized)
struct AppStateTests {
    let store = TokenStore(service: "com.coopertech.reframedthoughts.appstate-tests")

    @Test func noTokenRoutesToSignedOut() async {
        store.clear()
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub() }, devJWT: nil)
        await state.start()
        #expect(state.route == .signedOut)
    }
    @Test func tokenRoutesToIntro() async throws {
        try store.write("t")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { User(id: "u", hasVoice: true) }) })
        await state.start()
        #expect(state.route == .intro)
    }
    @Test func introNextWithoutVoiceRoutesToEnroll() async throws {
        try store.write("t")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { User(id: "u", hasVoice: false) }) })
        await state.start()
        state.continueFromIntro()
        #expect(state.route == .enroll)
    }
    @Test func introNextWithVoiceRoutesToMain() async throws {
        try store.write("t")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { User(id: "u", hasVoice: true) }) })
        await state.start()
        state.continueFromIntro()
        #expect(state.route == .main)
    }
    @Test func didEnrollSkipsIntro() async throws {
        try store.write("t")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { User(id: "u", hasVoice: false) }) })
        await state.start()
        state.continueFromIntro()
        state.didEnroll(User(id: "u", hasVoice: true))
        #expect(state.route == .main)
    }
    @Test func unauthenticatedOnStartClearsTokenAndSignsOut() async throws {
        try store.write("stale")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { throw APIError.unauthenticated }) })
        await state.start()
        #expect(state.route == .signedOut)
        #expect(store.read() == nil)
    }
    @Test func signInStoresTokenAndRebuildsAPIWithIt() async throws {
        store.clear()
        let seen = Captured<[String?]>([])
        let state = AppState(tokenStore: store, makeAPI: { token in
            seen.value.append(token)
            return .stub(signIn: { _ in ("jwt-1", User(id: "u", hasVoice: false)) })
        })
        await state.start()
        try await state.signIn(identityToken: "apple-id-token")
        #expect(store.read() == "jwt-1")
        #expect(state.route == .intro)
        #expect(seen.value.last == "jwt-1")
    }
    @Test func devJWTSkipsSignIn() async {
        store.clear()
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { User(id: "u", hasVoice: true) }) }, devJWT: "dev")
        await state.start()
        #expect(state.route == .intro)
    }
    @Test func handleUnauthenticatedSignsOut() async throws {
        try store.write("t")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { User(id: "u", hasVoice: true) }) })
        await state.start()
        state.handle(APIError.unauthenticated)
        #expect(state.route == .signedOut)
        #expect(store.read() == nil)
    }
    @Test func nonAuthErrorOnStartRoutesToFailedAndKeepsToken() async throws {
        try store.write("t")
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: { throw APIError.transport("offline") }) })
        await state.start()
        #expect(state.route == .failed("offline"))
        #expect(store.read() == "t")
    }
    @Test func retryAfterFailedRecovers() async throws {
        try store.write("t")
        let calls = Captured(0)
        let state = AppState(tokenStore: store, makeAPI: { _ in .stub(me: {
            calls.value += 1
            if calls.value == 1 { throw APIError.transport("offline") }
            return User(id: "u", hasVoice: true)
        }) })
        await state.start()
        #expect(state.route == .failed("offline"))
        await state.start()
        #expect(state.route == .intro)
    }
}

import Foundation
import Observation

@MainActor @Observable
final class AppState {
    enum Route: Equatable { case loading, signedOut, intro, enroll, main, failed(String) }
    private(set) var route: Route = .loading
    private(set) var user: User?
    private(set) var api: API

    private let tokenStore: TokenStore
    private let makeAPI: (String?) -> API
    private let devJWT: String?

    init(tokenStore: TokenStore = TokenStore(), makeAPI: @escaping (String?) -> API, devJWT: String? = AppConfig.devJWT()) {
        self.tokenStore = tokenStore; self.makeAPI = makeAPI; self.devJWT = devJWT
        self.api = makeAPI(tokenStore.read() ?? devJWT)
    }

    func start() async {
        guard let token = tokenStore.read() ?? devJWT else { route = .signedOut; return }
        api = makeAPI(token)
        do { user = try await api.me(); route = .intro } catch {
            if error is CancellationError { return }
            if case APIError.unauthenticated = error { signOut(); return }
            route = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
        }
    }

    func signIn(identityToken: String) async throws {
        let (token, user) = try await api.signIn(identityToken)
        try tokenStore.write(token)
        api = makeAPI(token)
        self.user = user; route = .intro
    }

    /// "Next" on the intro screen: enroll a voice first, or go straight to recording.
    func continueFromIntro() { route = user?.hasVoice == true ? .main : .enroll }

    func didEnroll(_ user: User) { self.user = user; route = .main }

    func signOut() { tokenStore.clear(); user = nil; api = makeAPI(nil); route = .signedOut }

    /// UNAUTHENTICATED signs out; cancellation is ignored; other errors are the caller's to show.
    func handle(_ error: Error) {
        if case APIError.unauthenticated = error { signOut() }
    }
}

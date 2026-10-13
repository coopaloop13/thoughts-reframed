import Foundation
import Observation

@MainActor @Observable
final class AppState {
    enum Route: Equatable { case loading, signedOut, enroll, main, failed(String) }
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
        do { routeFor(try await api.me()) } catch {
            if error is CancellationError { return }
            if case APIError.unauthenticated = error { signOut(); return }
            route = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
        }
    }

    func signIn(identityToken: String) async throws {
        let (token, user) = try await api.signIn(identityToken)
        try tokenStore.write(token)
        api = makeAPI(token)
        routeFor(user)
    }

    func didEnroll(_ user: User) { routeFor(user) }

    func signOut() { tokenStore.clear(); user = nil; api = makeAPI(nil); route = .signedOut }

    /// UNAUTHENTICATED signs out; cancellation is ignored; other errors are the caller's to show.
    func handle(_ error: Error) {
        if case APIError.unauthenticated = error { signOut() }
    }

    private func routeFor(_ user: User) { self.user = user; route = user.hasVoice ? .main : .enroll }
}

import Foundation
import Observation

@MainActor @Observable
final class AppState {
    enum Route: Equatable { case loading, signedOut, enroll, main }
    private(set) var route: Route = .loading
    private(set) var user: User?
    private(set) var api: API
    var lastError: String?

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
            handle(error)
            if route == .loading && !(error is CancellationError) { route = .signedOut }
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

    /// Central error policy: UNAUTHENTICATED signs out; cancellation is ignored; everything else is surfaced.
    func handle(_ error: Error) {
        if error is CancellationError { return }
        if case APIError.unauthenticated = error { signOut(); return }
        lastError = (error as? APIError)?.userMessage ?? error.localizedDescription
    }

    private func routeFor(_ user: User) { self.user = user; route = user.hasVoice ? .main : .enroll }
}

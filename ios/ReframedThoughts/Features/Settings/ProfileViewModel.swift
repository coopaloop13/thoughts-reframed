import Foundation
import Observation

@MainActor @Observable
final class ProfileViewModel {
    enum State: Equatable { case loading, loaded(String?), failed(String) }
    private(set) var state: State = .loading
    private let api: API
    private let onUnauthenticated: () -> Void
    init(api: API, onUnauthenticated: @escaping () -> Void) { self.api = api; self.onUnauthenticated = onUnauthenticated }

    func load() async {
        do { state = .loaded(try await api.me().profile) }
        catch APIError.unauthenticated { onUnauthenticated() }
        catch { state = .failed((error as? APIError)?.userMessage ?? error.localizedDescription) }
    }
}

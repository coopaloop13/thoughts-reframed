import Foundation

struct API {
    var signIn: @Sendable (String) async throws -> (token: String, user: User)
    var me: @Sendable () async throws -> User
    var enrollVoice: @Sendable (URL, String) async throws -> User
    var createSession: @Sendable (URL) async throws -> Session
    var sessions: @Sendable () async throws -> [Session]
    var session: @Sendable (String) async throws -> Session?
    var watchSession: @Sendable (String) -> AsyncThrowingStream<Session, Error>
    var deleteAccount: @Sendable () async throws -> Void
}

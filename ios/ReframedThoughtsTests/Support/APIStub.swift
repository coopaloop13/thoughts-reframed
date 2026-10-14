import Foundation
@testable import ReframedThoughts

/// Mutable box for capturing values from `@Sendable` stub closures (Swift 6 forbids mutating captured vars).
final class Captured<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

extension API {
    static func stub(
        signIn: @escaping @Sendable (String) async throws -> (token: String, user: User) = { _ in throw APIError.server("unstubbed signIn") },
        me: @escaping @Sendable () async throws -> User = { throw APIError.server("unstubbed me") },
        enrollVoice: @escaping @Sendable (URL, String) async throws -> User = { _, _ in throw APIError.server("unstubbed enrollVoice") },
        createSession: @escaping @Sendable (URL) async throws -> Session = { _ in throw APIError.server("unstubbed createSession") },
        sessions: @escaping @Sendable () async throws -> [Session] = { [] },
        session: @escaping @Sendable (String) async throws -> Session? = { _ in nil },
        watchSession: @escaping @Sendable (String) -> AsyncThrowingStream<Session, Error> = { _ in AsyncThrowingStream { $0.finish() } },
        deleteAccount: @escaping @Sendable () async throws -> Void = {},
        previewVoice: @escaping @Sendable () async throws -> URL = { throw APIError.server("unstubbed previewVoice") },
        sendTurn: @escaping @Sendable (String, URL) async throws -> Turn = { _, _ in throw APIError.server("unstubbed sendTurn") },
        watchTurn: @escaping @Sendable (String) -> AsyncThrowingStream<Turn, Error> = { _ in AsyncThrowingStream { $0.finish() } }
    ) -> API {
        API(signIn: signIn, me: me, enrollVoice: enrollVoice, createSession: createSession, sessions: sessions, session: session, watchSession: watchSession, deleteAccount: deleteAccount, previewVoice: previewVoice, sendTurn: sendTurn, watchTurn: watchTurn)
    }
}

extension Session {
    static func fixture(id: String = "s1", status: SessionStatus = .uploaded, reframedText: String? = nil, audioUrl: URL? = nil, error: String? = nil, createdAt: Date = Date(timeIntervalSince1970: 0), crisis: Bool = false, turns: [Turn] = []) -> Session {
        Session(id: id, status: status, transcript: "I always mess up", reframedText: reframedText, audioUrl: audioUrl, error: error, createdAt: createdAt, crisis: crisis, turns: turns)
    }
}

extension Turn {
    static func fixture(id: String = "t1", status: SessionStatus = .uploaded, userText: String? = "I think she hates me", agentText: String? = nil, audioUrl: URL? = nil, crisis: Bool = false, closing: Bool = false, error: String? = nil, createdAt: Date = Date(timeIntervalSince1970: 0)) -> Turn {
        Turn(id: id, status: status, userText: userText, agentText: agentText, audioUrl: audioUrl, crisis: crisis, closing: closing, error: error, createdAt: createdAt)
    }
}

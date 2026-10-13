import Apollo
import ApolloAPI
import ApolloWebSocket
import Foundation

extension API {
    static func live(config: AppConfig, token: String?) -> API {
        let client = ApolloClientFactory.make(config: config, token: token)
        return API(
            signIn: { identityToken in
                try await mapped {
                    let r = try await client.perform(mutation: GQL.SignInWithAppleMutation(identityToken: identityToken))
                    let p = try unwrap(r).signInWithApple
                    return (p.token, User(id: p.user.id, hasVoice: p.user.hasVoice))
                }
            },
            me: {
                try await mapped {
                    let r = try await client.fetch(query: GQL.MeQuery(), cachePolicy: .networkOnly)
                    let u = try unwrap(r).me
                    return User(id: u.id, hasVoice: u.hasVoice)
                }
            },
            enrollVoice: { url, text in
                try await mapped {
                    let file = try GraphQLFile(fieldName: "sample", originalName: "voice.m4a", mimeType: "audio/mp4", fileURL: url)
                    let r = try await client.upload(operation: GQL.EnrollVoiceMutation(sample: "sample", referenceText: text), files: [file])
                    let u = try unwrap(r).enrollVoice
                    return User(id: u.id, hasVoice: u.hasVoice)
                }
            },
            createSession: { url in
                try await mapped {
                    let file = try GraphQLFile(fieldName: "recording", originalName: "recording.m4a", mimeType: "audio/mp4", fileURL: url)
                    let r = try await client.upload(operation: GQL.CreateSessionMutation(recording: "recording"), files: [file])
                    return Session(try unwrap(r).createSession.fragments.sessionFields)
                }
            },
            sessions: {
                try await mapped {
                    let r = try await client.fetch(query: GQL.SessionsQuery(limit: 50, before: nil), cachePolicy: .networkOnly)
                    return try unwrap(r).sessions.map { Session($0.fragments.sessionFields) }
                }
            },
            session: { id in
                try await mapped {
                    let r = try await client.fetch(query: GQL.SessionQuery(id: id), cachePolicy: .networkOnly)
                    return try unwrap(r).session.map { Session($0.fragments.sessionFields) }
                }
            },
            watchSession: { id in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            let stream = try client.subscribe(subscription: GQL.SessionUpdatedSubscription(id: id),
                                                              cachePolicy: .networkOnly)
                            for try await r in stream {
                                let s = Session(try unwrap(r).sessionUpdated.fragments.sessionFields)
                                continuation.yield(s)
                                if s.status.isTerminal { break }
                            }
                            continuation.finish()
                        } catch {
                            let e = mapError(error)
                            continuation.finish(throwing: (e as? APIError) == .transport(APIError.networkUnavailable)
                                                ? APIError.transport(APIError.lostConnection) : e)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            deleteAccount: {
                try await mapped { _ = try unwrap(try await client.perform(mutation: GQL.DeleteAccountMutation())) }
            }
        )
    }

    /// Throws APIError for GraphQL errors; returns data otherwise.
    private static func unwrap<Op: GraphQLOperation>(_ response: GraphQLResponse<Op>) throws -> Op.Data {
        if let e = response.errors?.first { throw apiError(e) }
        guard let data = response.data else { throw APIError.server("Empty response") }
        return data
    }
    private static func apiError(_ e: GraphQLError) -> APIError {
        APIError.from(code: e.extensions?["code"] as? String, message: e.message ?? "Unexpected error.")
    }
    static func mapError(_ error: Error) -> Error {
        if let e = error as? APIError { return e }
        if error is CancellationError { return error }
        if (error as? URLError)?.code == .cancelled { return CancellationError() }
        if case .graphQLErrors(let errors) = error as? WebSocketTransport.Error, let first = errors.first {
            return apiError(first)
        }
        if error is WebSocketTransport.Error || error is URLError { return APIError.transport(APIError.networkUnavailable) }
        return APIError.transport(error.localizedDescription)
    }
    /// Runs `body`, converting any thrown error to `APIError`.
    private static func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw mapError(error) }
    }
}

extension Session {
    init(_ f: GQL.SessionFields) {
        self.init(id: f.id, status: SessionStatus(rawValue: f.status.rawValue) ?? .failed,
                  transcript: f.transcript, reframedText: f.reframedText,
                  audioUrl: f.audioUrl.flatMap(URL.init(string:)), error: f.error,
                  createdAt: Session.parseDate(f.createdAt) ?? .distantPast)
    }
}

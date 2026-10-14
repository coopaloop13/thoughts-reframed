import Foundation

struct User: Equatable, Hashable, Sendable { let id: String; let hasVoice: Bool; var profile: String? = nil }

enum SessionStatus: String, Equatable, Hashable, Sendable {
    case uploaded = "UPLOADED", transcribing = "TRANSCRIBING", reframing = "REFRAMING",
         synthesizing = "SYNTHESIZING", completed = "COMPLETED", failed = "FAILED"
    var isTerminal: Bool { self == .completed || self == .failed }
}

struct Turn: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let status: SessionStatus
    let userText: String?
    let agentText: String?
    let audioUrl: URL?
    let crisis: Bool
    let closing: Bool
    let error: String?
    let createdAt: Date
}

struct Session: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let status: SessionStatus
    let transcript: String?
    let reframedText: String?
    let audioUrl: URL?
    let error: String?
    let createdAt: Date
    var crisis: Bool = false
    var turns: [Turn] = []

    static func parseDate(_ s: String) -> Date? {
        (try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(s, strategy: .iso8601))
    }
}

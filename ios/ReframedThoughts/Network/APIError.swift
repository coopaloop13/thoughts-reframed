import Foundation

enum APIError: Error, Equatable {
    case unauthenticated, invalidAppleToken, voiceNotEnrolled, notFound
    case server(String), transport(String)

    static func from(code: String?, message: String) -> APIError {
        switch code {
        case "UNAUTHENTICATED": .unauthenticated
        case "INVALID_APPLE_TOKEN": .invalidAppleToken
        case "VOICE_NOT_ENROLLED": .voiceNotEnrolled
        case "NOT_FOUND": .notFound
        default: .server(message)
        }
    }
    var userMessage: String {
        switch self {
        case .unauthenticated: "Please sign in again."
        case .invalidAppleToken: "Apple sign-in failed. Please try again."
        case .voiceNotEnrolled: "Set up your voice first."
        case .notFound: "That session no longer exists."
        case .server(let m), .transport(let m): m
        }
    }
}

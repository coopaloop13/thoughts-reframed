import Testing
@testable import ReframedThoughts

struct APIErrorTests {
    @Test func mapsCodes() {
        #expect(APIError.from(code: "UNAUTHENTICATED", message: "x") == .unauthenticated)
        #expect(APIError.from(code: "VOICE_NOT_ENROLLED", message: "x") == .voiceNotEnrolled)
        #expect(APIError.from(code: "NOT_FOUND", message: "x") == .notFound)
        #expect(APIError.from(code: "INVALID_APPLE_TOKEN", message: "x") == .invalidAppleToken)
        #expect(APIError.from(code: nil, message: "Unexpected error.") == .server("Unexpected error."))
    }
}

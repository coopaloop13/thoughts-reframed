import Testing
@testable import ReframedThoughts

struct CodegenTests {
    @Test func operationsExist() {
        _ = GQL.MeQuery()
        _ = GQL.SessionUpdatedSubscription(id: "x")
        _ = GQL.TurnUpdatedSubscription(id: "x")
        _ = GQL.SendTurnMutation(sessionId: "s", recording: "recording")
        #expect(GQL.SessionStatus.completed.rawValue == "COMPLETED")
    }
}

import Testing
@testable import ReframedThoughts

struct CodegenTests {
    @Test func operationsExist() {
        _ = GQL.MeQuery()
        _ = GQL.SessionUpdatedSubscription(id: "x")
        #expect(GQL.SessionStatus.completed.rawValue == "COMPLETED")
    }
}

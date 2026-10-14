import Testing
import Foundation
@testable import ReframedThoughts

struct ModelsTests {
    @Test func statusTerminal() {
        #expect(SessionStatus.completed.isTerminal)
        #expect(SessionStatus.failed.isTerminal)
        #expect(!SessionStatus.synthesizing.isTerminal)
        #expect(SessionStatus(rawValue: "REFRAMING") == .reframing)
    }
    @Test func sessionDefaultsHaveNoTurnsAndNoCrisis() {
        let s = Session.fixture()
        #expect(s.turns.isEmpty)
        #expect(!s.crisis)
        let t = Turn.fixture(agentText: "hi", closing: true)
        #expect(t.closing && t.agentText == "hi" && !t.crisis)
    }
    @Test func iso8601Parsing() {
        let d = Session.parseDate("2026-01-01T00:00:02.000Z")
        #expect(d == Date(timeIntervalSince1970: 1_767_225_602))
        #expect(Session.parseDate("garbage") == nil)
    }
}

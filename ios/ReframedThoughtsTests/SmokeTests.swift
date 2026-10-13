import Testing
@testable import ReframedThoughts

struct SmokeTests {
    @Test func appModuleLinks() { #expect(AppInfo.name == "Reframed") }
}

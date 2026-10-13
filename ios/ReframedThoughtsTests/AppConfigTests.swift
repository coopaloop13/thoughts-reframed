import Testing
import Foundation
@testable import ReframedThoughts

struct AppConfigTests {
    @Test func envWins() {
        let url = AppConfig.baseURL(env: ["API_BASE_URL": "http://localhost:8080"], infoPlist: { _ in "https://prod.example" })
        #expect(url.absoluteString == "http://localhost:8080")
    }
    @Test func plistFallback() {
        let url = AppConfig.baseURL(env: [:], infoPlist: { key in key == "APIBaseURL" ? "https://prod.example" : nil })
        #expect(url.absoluteString == "https://prod.example")
    }
    @Test func graphqlEndpoints() {
        let c = AppConfig(base: URL(string: "https://prod.example")!)
        #expect(c.httpURL.absoluteString == "https://prod.example/graphql")
        #expect(c.wsURL.absoluteString == "wss://prod.example/graphql")
        #expect(AppConfig(base: URL(string: "http://localhost:8080")!).wsURL.absoluteString == "ws://localhost:8080/graphql")
    }
    @Test func devJWT() {
        #expect(AppConfig.devJWT(env: ["DEV_JWT": "abc"]) == "abc")
        #expect(AppConfig.devJWT(env: ["DEV_JWT": ""]) == nil)
    }
}

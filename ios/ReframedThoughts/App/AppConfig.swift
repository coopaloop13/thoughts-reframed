import Foundation

struct AppConfig: Sendable {
    let base: URL
    var httpURL: URL { base.appending(path: "graphql") }
    var wsURL: URL {
        var c = URLComponents(url: httpURL, resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        return c.url!
    }

    static func baseURL(env: [String: String] = ProcessInfo.processInfo.environment,
                        infoPlist: (String) -> String? = { Bundle.main.object(forInfoDictionaryKey: $0) as? String }) -> URL {
        if let s = env["API_BASE_URL"], !s.isEmpty, let u = URL(string: s) { return u }
        if let s = infoPlist("APIBaseURL"), let u = URL(string: s) { return u }
        return URL(string: "http://localhost:8080")!
    }
    static func devJWT(env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard let t = env["DEV_JWT"], !t.isEmpty else { return nil }
        return t
    }
    static let current = AppConfig(base: baseURL())
}

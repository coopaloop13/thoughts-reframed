import SwiftUI

@main
struct ReframedThoughtsApp: App {
    @State private var app = AppState(makeAPI: { API.live(config: .current, token: $0) })
    var body: some Scene { WindowGroup { RootView().environment(app) } }
}

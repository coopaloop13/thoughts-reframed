import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Group {
            switch app.route {
            case .loading: ProgressView()
            case .signedOut: SignInView()
            case .enroll: EnrollVoiceView()
            case .main: MainTabView()
            }
        }
        .task { await app.start() }
    }
}

// Temporary placeholders; Task 8 replaces it.
struct MainTabView: View { var body: some View { Text("Main") } }

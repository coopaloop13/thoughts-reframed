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

// Temporary placeholders; Tasks 6 and 8 replace them.
struct EnrollVoiceView: View { var body: some View { Text("Enroll") } }
struct MainTabView: View { var body: some View { Text("Main") } }

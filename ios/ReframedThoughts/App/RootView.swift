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
            case .failed(let msg):
                VStack(spacing: 16) {
                    Text(msg).multilineTextAlignment(.center)
                    Button("Retry") { Task { await app.start() } }.buttonStyle(.borderedProminent)
                    Button("Sign out", role: .destructive) { app.signOut() }
                }.padding()
            }
        }
        .task { await app.start() }
    }
}

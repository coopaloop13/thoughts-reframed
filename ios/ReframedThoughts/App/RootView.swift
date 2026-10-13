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
                VStack(spacing: Theme.spacing) {
                    Text(msg).multilineTextAlignment(.center)
                    Button("Retry") { Task { await app.start() } }.buttonStyle(PrimaryButtonStyle())
                    Button("Sign out") { app.signOut() }.buttonStyle(SecondaryButtonStyle())
                }.padding(Theme.spacing)
            }
        }
        .foregroundStyle(Color.bark)
        .tint(.forest)
        .background(Color.sand.ignoresSafeArea())
        .task { await app.start() }
    }
}

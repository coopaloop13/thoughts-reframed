import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var error: String?

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Spacer()
            Image(systemName: "leaf.fill").font(.system(size: 44)).foregroundStyle(Color.forest)
            Text("Reframed").font(.display(.largeTitle))
            Text("Say the thought out loud.\nHear it back, kinder, in your own voice.")
                .multilineTextAlignment(.center).foregroundStyle(Color.muted)
            Spacer()
            SignInWithAppleButton(.signIn) { req in
                req.requestedScopes = []
            } onCompletion: { result in
                Task { await complete(result) }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 52).clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            if let error { Text(error).font(.footnote).multilineTextAlignment(.center) }
        }
        .padding(Theme.spacing)
        .background(Color.sand.ignoresSafeArea())
    }

    private func complete(_ result: Result<ASAuthorization, Error>) async {
        do {
            guard let cred = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
                error = "Apple did not return an identity token."; return
            }
            try await app.signIn(identityToken: token)
        } catch {
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            self.error = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}

import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var app
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Reframed").font(.largeTitle.bold())
            Text("Say the thought. Hear it reframed, in your own voice.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn) { req in
                req.requestedScopes = []
            } onCompletion: { result in
                Task { await complete(result) }
            }
            .signInWithAppleButtonStyle(.black).frame(height: 50)
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .padding()
    }

    private func complete(_ result: Result<ASAuthorization, Error>) async {
        do {
            guard let cred = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
                error = "Apple did not return an identity token."; return
            }
            try await app.signIn(identityToken: token)
        } catch {
            self.error = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}

// Native Sign in with Apple button. Generates a per-request nonce (raw value
// for Supabase, SHA256 on the Apple request), then hands the resulting ID
// token to AuthService, which validates it via signInWithIdToken.
//
// Apple returns the user's full name ONLY on the very first authorization, so
// we forward it on success and AuthService persists it as the nickname.

import AuthenticationServices
import SwiftUI

struct AppleSignInButton: View {
    @Environment(AuthService.self) private var auth
    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = AppleSignInBridge.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInBridge.sha256(nonce)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(.rect(cornerRadius: Radius.lg))
        // The system control labels itself from the *device* language, so on
        // a non-Chinese phone it reads "Continue with Apple" next to the zh
        // 繼續使用 Google — the one button that ignores the app's pinned
        // locale. Draw our own label (per HIG: Apple logo + approved wording)
        // and let touches fall through to the real control underneath.
        .overlay {
            HStack(spacing: Space.s2) {
                Image(systemName: "applelogo")
                    .font(.system(size: 17, weight: .medium))
                Text("繼續使用 Apple")
                    .font(.system(size: 15, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: .rect(cornerRadius: Radius.lg))
            .allowsHitTesting(false)
        }
        .disabled(auth.loading)
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                auth.appleSignInDidFail(AppleSignInBridge.MissingTokenError())
                return
            }
            let fullName = credential.fullName
                .map { PersonNameComponentsFormatter().string(from: $0) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName) }
        case let .failure(error):
            // ASAuthorizationError.canceled is a normal user dismissal — stay quiet.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            auth.appleSignInDidFail(error)
        }
    }
}

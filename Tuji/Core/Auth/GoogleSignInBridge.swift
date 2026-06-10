// Thin SwiftUI → UIKit bridge for GoogleSignIn-iOS.
//
// The SDK requires a presenting UIViewController which SwiftUI doesn't
// expose directly. We grab the key window's root VC at the moment of
// sign-in, hand it to the SDK, and bridge the completion callback into
// an async Result so AuthService can await it.

import Foundation
import OSLog
import UIKit
import GoogleSignIn

@MainActor
enum GoogleSignInBridge {
    private static let log = Logger(subsystem: "app.tuji.ios", category: "google-signin")

    enum GoogleSignInError: LocalizedError {
        case noPresentingViewController
        case missingIdToken
        case userCancelled

        var errorDescription: String? {
            switch self {
            case .noPresentingViewController: "找不到可呈現的視窗（請重試）"
            case .missingIdToken: "Google 沒回傳 ID token"
            case .userCancelled: "已取消"
            }
        }
    }

    /// Presents Google's sign-in flow and returns the resulting ID token.
    /// Uses ASWebAuthenticationSession under the hood, so the system
    /// captures the callback URL — no manual onOpenURL plumbing required.
    static func signIn() async throws -> String {
        guard let rootVC = topViewController() else {
            log.error("no root VC for Google sign-in")
            throw GoogleSignInError.noPresentingViewController
        }

        return try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
                if let error {
                    let ns = error as NSError
                    // User-cancelled is GIDSignInError.canceled (-5).
                    if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
                        cont.resume(throwing: GoogleSignInError.userCancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let idToken = result?.user.idToken?.tokenString else {
                    cont.resume(throwing: GoogleSignInError.missingIdToken)
                    return
                }
                cont.resume(returning: idToken)
            }
        }
    }

    /// Forwards Google's own sign-out so cached credentials don't leak
    /// across users on the device. Called by AuthService.signOut().
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.rootViewController }
            .first
    }
}

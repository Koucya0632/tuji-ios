// Crypto helpers for Sign in with Apple's nonce dance.
//
// We hand Apple a SHA256-hashed nonce on the authorization request; the
// resulting ID token then carries that hash in its `nonce` claim. Supabase
// needs the original raw value to verify the token, so the button keeps the
// raw nonce around and passes it to signInWithIdToken.

import CryptoKit
import Foundation

enum AppleSignInBridge {
    /// Raised when Apple reports success but the credential is missing the
    /// identity token we need to hand to Supabase.
    struct MissingTokenError: LocalizedError {
        var errorDescription: String? {
            "Apple 沒回傳登入憑證，請重試"
        }
    }

    /// Cryptographically secure random string for one authorization request.
    /// Rejection-samples bytes < charset count to avoid modulo bias (Apple's
    /// official Sign in with Apple sample uses the same approach).
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                fatalError("SecRandomCopyBytes failed with OSStatus \(status)")
            }
            for random in randoms where remaining > 0 {
                if Int(random) < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// Lowercase hex SHA256 — what Apple expects on the request's `nonce`.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

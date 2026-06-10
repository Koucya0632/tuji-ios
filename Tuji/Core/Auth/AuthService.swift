// Auth state machine + Supabase glue.
//
// State transitions:
//   .checking  (app launch)
//      └─ restoreSession() ──► .signedIn  if persisted session exists
//                          └─► .signedOut otherwise
//   .signedOut
//      ├─ signUp()  ──► .signedIn  (or stays .signedOut if email confirm required)
//      └─ signIn()  ──► .signedIn
//   .signedIn
//      └─ signOut() ──► .signedOut

import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(SessionUser)
    }

    static let shared = AuthService()

    private(set) var state: State = .checking
    var error: String?
    var loading: Bool = false

    private let supabase = SupabaseProvider.client
    private let log = Logger(subsystem: "app.tuji.ios", category: "auth")

    private init() {}

    // MARK: - Lifecycle

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            state = .signedIn(SessionUser(from: session.user))
            log.info("session restored uid=\(session.user.id.uuidString, privacy: .public)")
        } catch {
            state = .signedOut
            log.info("no existing session")
        }
    }

    // MARK: - Email

    func signUp(email: String, password: String, username: String) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let resp = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["username": .string(username)]
            )
            if let session = resp.session {
                state = .signedIn(SessionUser(from: session.user))
                log.info("signup ok uid=\(session.user.id.uuidString, privacy: .public)")
            } else {
                // Supabase dev project has email confirmation enabled by default.
                error = "已寄出確認信，請開信箱點連結後再登入。"
                log.info("signup pending email confirmation")
            }
        } catch {
            self.error = friendly(error)
            log.error("signup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signIn(email: String, password: String) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            state = .signedIn(SessionUser(from: session.user))
            log.info("signin ok uid=\(session.user.id.uuidString, privacy: .public)")
        } catch {
            self.error = friendly(error)
            log.error("signin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - OAuth (stubs — W2 follow-up)

    func signInWithApple(idToken: String, nonce: String) async {
        // TODO: requires Apple Developer Program (Service ID + Sign in Key).
        error = "Apple 登入待 Apple Developer Program 通過後開啟。"
    }

    func signInWithGoogle(idToken: String, nonce: String) async {
        // TODO: requires GoogleSignIn SDK + presenting view controller.
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: idToken, nonce: nonce)
            )
            state = .signedIn(SessionUser(from: session.user))
        } catch {
            self.error = friendly(error)
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await supabase.auth.signOut()
        state = .signedOut
        error = nil
        log.info("signed out")
    }

    // MARK: - For APIClient

    func validAccessToken() async throws -> String {
        let session = try await supabase.auth.session
        return session.accessToken
    }

    // MARK: - Helpers

    private func friendly(_ err: Error) -> String {
        let msg = err.localizedDescription
        if msg.localizedCaseInsensitiveContains("invalid login credentials") {
            return "Email 或密碼錯誤"
        }
        if msg.localizedCaseInsensitiveContains("user already registered") {
            return "此 Email 已註冊，請改用登入"
        }
        if msg.localizedCaseInsensitiveContains("rate limit") {
            return "嘗試太頻繁，請稍後再試"
        }
        if msg.localizedCaseInsensitiveContains("password should be") {
            return "密碼太短（至少 8 字）"
        }
        if msg.localizedCaseInsensitiveContains("email address") &&
           msg.localizedCaseInsensitiveContains("invalid") {
            return "Email 格式或網域不被接受"
        }
        return msg
    }
}

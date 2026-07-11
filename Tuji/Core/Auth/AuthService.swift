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
        case guest // browsing without an account
        case signedIn(SessionUser)
    }

    enum SignUpResult: Equatable {
        case signedIn
        case pendingEmailConfirmation
        case failed
    }

    static let shared = AuthService()

    private(set) var state: State = .checking
    var error: String?
    var loading: Bool = false

    private let supabase = SupabaseProvider.client
    private let log = Logger(subsystem: "app.tuji.ios", category: "auth")
    private var users: UserRepository {
        LiveUserRepository.shared
    }

    private init() {}

    // MARK: - Lifecycle

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            state = .signedIn(SessionUser(from: session.user))
            log.info("session restored uid=\(session.user.id.uuidString, privacy: .public)")
        } catch {
            // `supabase.auth.session` refreshes an expired token over the
            // network. If that refresh fails while a session is still
            // cached locally — i.e. the failure isn't "no session at all"
            // — the likely cause is the device being offline. Stay signed
            // in with the stale cached session rather than bouncing an
            // already-authenticated user out to Welcome for a transient
            // network hiccup; it'll refresh next time we have connectivity.
            if let cached = supabase.auth.currentSession, (error as? AuthError) != .sessionMissing {
                state = .signedIn(SessionUser(from: cached.user))
                log
                    .info(
                        "session refresh failed, keeping cached session uid=\(cached.user.id.uuidString, privacy: .public)"
                    )
            } else {
                state = .signedOut
                log.info("no existing session")
            }
        }
    }

    // MARK: - Guest mode

    /// True when the Welcome screen was reached by leaving guest mode (Me tab
    /// / Today hero 登入/註冊) rather than at first launch. Welcome uses it to
    /// offer a close button back to guest browsing — otherwise the screen is
    /// an exit-less dead end for someone who tapped in by accident.
    private(set) var cameFromGuest = false

    func enterGuestMode() {
        guard case .signedOut = state else { return }
        state = .guest
        cameFromGuest = false
        log.info("entered guest mode")
    }

    /// Called from MainTabsView's "登入 / 註冊" button so guest can land
    /// on Welcome and pick a flow.
    func exitGuestMode() {
        guard case .guest = state else { return }
        state = .signedOut
        cameFromGuest = true
        log.info("exited guest mode")
    }

    // MARK: - Email

    func signUp(email: String, password: String, username: String) async -> SignUpResult {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let resp = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["username": .string(username)],
                redirectTo: emailConfirmationRedirectURL
            )
            if let session = resp.session {
                state = .signedIn(SessionUser(from: session.user))
                await syncLocalCacheToServer()
                log.info("signup ok uid=\(session.user.id.uuidString, privacy: .public)")
                return .signedIn
            } else {
                log.info("signup pending email confirmation")
                return .pendingEmailConfirmation
            }
        } catch {
            self.error = friendly(error)
            log.error("signup failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    func signIn(email: String, password: String) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            state = .signedIn(SessionUser(from: session.user))
            await syncLocalCacheToServer()
            log.info("signin ok uid=\(session.user.id.uuidString, privacy: .public)")
        } catch {
            self.error = friendly(error)
            log.error("signin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - OAuth

    /// Validates an Apple ID token against Supabase via signInWithIdToken. The
    /// raw `nonce` must match the SHA256 the button put on the Apple request.
    /// `fullName` is non-nil only on the user's FIRST authorization (Apple
    /// policy), so we capture it then — see captureAppleNameIfNeeded.
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            state = .signedIn(SessionUser(from: session.user))
            await syncLocalCacheToServer()
            await captureAppleNameIfNeeded(fullName)
            log.info("apple signin ok uid=\(session.user.id.uuidString, privacy: .public)")
        } catch {
            self.error = friendly(error)
            log.error("apple signin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Surfaces a non-cancellation Apple sign-in failure. AppleSignInButton
    /// filters out user cancellation before calling this.
    func appleSignInDidFail(_ error: Error) {
        self.error = friendly(error)
        log.error("apple signin failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Drives the full Google native flow: GoogleSignInBridge gets the
    /// ID token, then signInWithIdToken validates it against Supabase.
    /// Supabase project must have **Skip nonce checks ON** for this to
    /// succeed — the GoogleSignIn iOS SDK doesn't expose the nonce
    /// parameter (Supabase iOS guide reflects this).
    func signInWithGoogle() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let idToken = try await GoogleSignInBridge.signIn()
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken
                )
            )
            state = .signedIn(SessionUser(from: session.user))
            await syncLocalCacheToServer()
            log.info("google signin ok uid=\(session.user.id.uuidString, privacy: .public)")
        } catch GoogleSignInBridge.GoogleSignInError.userCancelled {
            log.info("google signin cancelled by user")
        } catch {
            self.error = friendly(error)
            log.error("google signin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sign out

    func signOut() async {
        // Drop the device's push token first so the previous account
        // stops receiving notifications. Best-effort; runs in parallel
        // with the Supabase sign-out call below.
        async let unregisterPush: Void = PushNotificationService.shared.unregister()

        try? await supabase.auth.signOut()
        GoogleSignInBridge.signOut() // clears cached Google credentials too

        _ = await unregisterPush

        state = .signedOut
        cameFromGuest = false
        error = nil
        log.info("signed out")
    }

    // MARK: - For APIClient

    func validAccessToken() async throws -> String {
        let session = try await supabase.auth.session
        return session.accessToken
    }

    // MARK: - Profile

    /// Optimistically reflect a profile edit in the in-memory session so the
    /// UI updates immediately, without waiting for the auth token's metadata
    /// to refresh. The backend has already persisted the change.
    func applyNickname(_ nickname: String?) {
        guard case let .signedIn(user) = state else { return }
        state = .signedIn(user.withNickname(nickname))
    }

    func applyProfile(nickname: String?, avatar: String?) {
        guard case let .signedIn(user) = state else { return }
        state = .signedIn(user.withProfile(nickname: nickname, avatar: avatar))
    }

    // MARK: - Local cache sync

    /// Uploads the device's anonymous favorites/learned to the server so a
    /// new account inherits whatever the user touched in guest mode.
    /// Best-effort — failures are logged and silently swallowed.
    private func syncLocalCacheToServer() async {
        let snapshot = LocalCache.shared.syncSnapshot
        guard !snapshot.favorites.isEmpty || !snapshot.learned.isEmpty else {
            return
        }
        do {
            try await self.users.syncLocalCache(snapshot)
            log.info("synced \(snapshot.favorites.count) favs + \(snapshot.learned.count) learned to server")
        } catch {
            log.error("sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var emailConfirmationRedirectURL: URL? {
        let fallback = URL(string: "https://everyday-english-picture-dictionary.vercel.app/auth/confirmed")
        guard let str = Bundle.main.object(forInfoDictionaryKey: "TUJI_BASE_URL") as? String,
              let baseURL = URL(string: str)
        else {
            return fallback
        }
        return baseURL.appending(path: "auth/confirmed")
    }

    /// Apple hands over the user's name only on the FIRST authorization, so a
    /// present name means a fresh account — persist it as the nickname while we
    /// have the one chance (design book §Auth). Skips if a nickname already
    /// exists. Best-effort: failures are logged and swallowed.
    private func captureAppleNameIfNeeded(_ fullName: String?) async {
        guard let fullName, !fullName.isEmpty else { return }
        guard case let .signedIn(user) = state, (user.nickname ?? "").isEmpty else { return }
        do {
            _ = try await self.users.updateProfile(ProfileUpdatePayload(nickname: fullName, avatar: nil))
            applyNickname(fullName)
            log.info("captured apple full name into profile")
        } catch {
            log.error("apple name capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func friendly(_ err: Error) -> String {
        let msg = err.localizedDescription
        if msg.localizedCaseInsensitiveContains("invalid login credentials") {
            return tujiLocalized("Email 或密碼錯誤")
        }
        if msg.localizedCaseInsensitiveContains("user already registered") {
            return tujiLocalized("此 Email 已註冊，請改用登入")
        }
        if msg.localizedCaseInsensitiveContains("rate limit") {
            return tujiLocalized("嘗試太頻繁，請稍後再試")
        }
        if msg.localizedCaseInsensitiveContains("provider"),
           msg.localizedCaseInsensitiveContains("not enabled")
        {
            return tujiLocalized("Apple 登入尚未啟用，請稍後再試")
        }
        if msg.localizedCaseInsensitiveContains("password should be") {
            return tujiLocalized("密碼太短（至少 8 字）")
        }
        if msg.localizedCaseInsensitiveContains("email address"),
           msg.localizedCaseInsensitiveContains("invalid")
        {
            return tujiLocalized("Email 格式或網域不被接受")
        }
        return msg
    }
}

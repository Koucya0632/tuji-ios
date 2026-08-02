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
            await hydrateProfile()
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

    /// Registration creates only the server-minted UID and default avatar.
    /// A public nickname is optional and goes through Profile edit moderation
    /// only after authentication.
    func signUp(email: String, password: String) async -> SignUpResult {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let resp = try await supabase.auth.signUp(
                email: email,
                password: password,
                redirectTo: emailConfirmationRedirectURL
            )
            if let session = resp.session {
                state = .signedIn(SessionUser(from: session.user))
                await syncLocalCacheToServer()
                await hydrateProfile()
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
            await hydrateProfile()
            log.info("signin ok uid=\(session.user.id.uuidString, privacy: .public)")
        } catch {
            self.error = friendly(error)
            log.error("signin failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - OAuth

    /// Validates an Apple ID token against Supabase via signInWithIdToken. The
    /// raw `nonce` must match the SHA256 the button put on the Apple request.
    ///
    /// `fullName` is accepted and deliberately DISCARDED. Apple sends it only on
    /// the first authorization, and we used to persist it into `nickname` — a
    /// real name the user never typed, written silently. That is now the display
    /// name shown on every public page, so seeding it would publish a legal name
    /// nobody offered. A name reaches the community only by being typed into a
    /// field labelled 暱稱.
    func signInWithApple(idToken: String, nonce: String, fullName _: String?) async {
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
            await hydrateProfile()
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
            await hydrateProfile()
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

        // The atlas store is an app-lifetime singleton whose sync merge is
        // additive, so without an explicit wipe the next account would still
        // see this account's 自製圖鑑; the capture queue likewise persists its
        // jobs and would resume them under the next account's session.
        AtlasStore.shared.reset()
        AtlasCaptureQueue.shared.reset()

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

    /// Reconciles the session's `user_metadata` mirror against `profiles`.
    ///
    /// The UID lives in `profiles.username`; the session only carries a copy,
    /// minted when the token was issued. Nothing the client does can refresh
    /// that copy on demand, so an account whose UID was assigned or rewritten
    /// server-side reads as nil (OAuth signups, which never had the key) or as
    /// a stale pre-migration handle (email signups) until the token rolls over.
    /// Both render as a broken 我的公開主頁.
    ///
    /// Best-effort: on failure the cached session stands, so this never costs
    /// an offline launch.
    private func hydrateProfile() async {
        guard case let .signedIn(user) = state else { return }
        guard let me = try? await users.loadMe().user else { return }
        let merged = user.merging(username: me.username, nickname: me.nickname, avatar: me.avatar)
        guard merged != user else { return }
        state = .signedIn(merged)
        log.info("profile mirror reconciled from server")
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

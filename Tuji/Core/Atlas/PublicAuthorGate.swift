// The consent check both publish paths (單張 / 合集) run before they publish.
//
// The server is the authority — /api/atlas/items/{id}/publish and the
// collection equivalent both refuse with 409 `author_identity_required` — so
// this exists only to put the setup screen in front of the user *before* they
// hit that wall, and to recognise the wall when a check could not run.

import Foundation

@MainActor
struct PublicAuthorGate {
    private let repo: PublicAuthorIdentityEditing

    init(repo: PublicAuthorIdentityEditing = LiveUserRepository.shared) {
        self.repo = repo
    }

    /// The identity to seed the 公開作者身分 sheet with, or nil when the user
    /// already confirmed one and publishing may proceed.
    ///
    /// Fails OPEN: if the lookup itself fails we let the publish attempt run,
    /// because the server still enforces the gate. Showing the consent screen
    /// to someone who already agreed — on nothing more than a dropped
    /// request — reads as the app forgetting them.
    func identityNeedingConfirmation() async -> PublicAuthorIdentity? {
        guard let identity = try? await self.repo.publicAuthorIdentity() else { return nil }
        return identity.confirmed ? nil : identity
    }

    /// True when a publish failed *only* because there is no confirmed identity
    /// — the one error the caller can fix by showing the sheet.
    static func isIdentityRequired(_ error: Error) -> Bool {
        guard let apiError = error as? APIError,
              case let .server(status, _) = apiError
        else { return false }
        return status == 409
    }
}

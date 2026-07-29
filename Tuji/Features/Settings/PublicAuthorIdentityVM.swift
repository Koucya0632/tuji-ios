// View model for PublicAuthorIdentitySheet (公開作者身分).
//
// Owns the whole editing decision — what a valid handle is, whether the form
// may be submitted, what the server said — so the sheet stays presentation-only
// and the rules are testable without SwiftUI (mirrors CollectionEditVM).
//
// The client validation here is convenience, not enforcement: /api/users/
// public-author re-checks everything, and the publish routes refuse with 409
// until the identity exists.

import Foundation
import Observation

@MainActor
@Observable
final class PublicAuthorIdentityVM {
    /// Same shape the server accepts and the author route can look up: anything
    /// outside this set would need escaping in a URL path.
    private static let handleCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"
    )
    private static let handleLength = 2...40
    static let displayNameMax = 20

    var handle: String
    var displayName: String
    private(set) var avatar: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// True when the user has never confirmed — the sheet is then a consent
    /// step, not an edit, and says so.
    let isFirstTime: Bool

    private let repo: PublicAuthorIdentityEditing

    init(
        identity: PublicAuthorIdentity,
        repo: PublicAuthorIdentityEditing = LiveUserRepository.shared
    ) {
        self.handle = identity.handle
        self.displayName = identity.displayName
        self.avatar = identity.avatar
        self.isFirstTime = !identity.confirmed
        self.repo = repo
    }

    var trimmedHandle: String {
        self.handle.trimmingCharacters(in: .whitespaces)
    }

    var trimmedDisplayName: String {
        self.displayName.trimmingCharacters(in: .whitespaces)
    }

    var handleIsValid: Bool {
        let handle = self.trimmedHandle
        return Self.handleLength.contains(handle.count)
            && CharacterSet(charactersIn: handle).isSubset(of: Self.handleCharacters)
    }

    var displayNameIsValid: Bool {
        let name = self.trimmedDisplayName
        return !name.isEmpty && name.count <= Self.displayNameMax
    }

    var canSubmit: Bool {
        !self.isSaving && self.handleIsValid && self.displayNameIsValid
    }

    /// Persists the identity. Returns true when the caller may proceed with
    /// whatever it was gating (publishing an item or a collection).
    func save() async -> Bool {
        guard self.canSubmit else { return false }
        self.isSaving = true
        self.errorMessage = nil
        defer { self.isSaving = false }
        do {
            let payload = PublicAuthorIdentityPayload(
                handle: self.trimmedHandle,
                displayName: self.trimmedDisplayName,
                avatar: self.avatar
            )
            _ = try await self.repo.setPublicAuthorIdentity(payload)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}

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
    /// Fallback only — the live limit comes down with the identity payload.
    static let defaultBioMax = 80

    var handle: String
    var displayName: String
    var bio: String
    private(set) var avatar: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    /// Server-owned, so the counter can't disagree with the rule that rejects.
    let bioMax: Int

    /// What the identity fields looked like on open. Used to tell a bio-only
    /// edit apart from a rename while the cooldown is running.
    private let originalHandle: String
    private let originalDisplayName: String

    /// True when the user has never confirmed — the sheet is then a consent
    /// step, not an edit, and says so.
    let isFirstTime: Bool

    /// False while the rename cooldown is running. The fields are disabled and
    /// the sheet says when they unlock: being refused after retyping your own
    /// name is a worse experience than being told up front.
    let isEditable: Bool
    /// Localized unlock date, or nil when nothing is locked.
    let nextChangeText: String?

    private let repo: PublicAuthorIdentityEditing

    init(
        identity: PublicAuthorIdentity,
        repo: PublicAuthorIdentityEditing = LiveUserRepository.shared
    ) {
        self.handle = identity.handle
        self.displayName = identity.displayName
        self.bio = identity.bio ?? ""
        self.bioMax = identity.bioMax ?? Self.defaultBioMax
        self.avatar = identity.avatar
        self.isFirstTime = !identity.confirmed
        self.isEditable = identity.isEditable
        self.nextChangeText = Self.unlockText(identity.nextChangeAt)
        self.originalHandle = identity.handle.trimmingCharacters(in: .whitespaces)
        self.originalDisplayName = identity.displayName.trimmingCharacters(in: .whitespaces)
        self.repo = repo
    }

    /// The server sends an ISO timestamp; the sheet shows a plain date.
    /// Reuses `ReviewSchedule.parseISO` because Postgres timestamps arrive with
    /// fractional seconds, which a default `ISO8601DateFormatter` rejects.
    private static func unlockText(_ iso: String?) -> String? {
        guard let iso, let date = ReviewSchedule.parseISO(iso) else { return nil }
        return date.formatted(.dateTime.year().month().day())
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

    var trimmedBio: String {
        self.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A bio may be empty — clearing it is a legitimate edit.
    var bioIsValid: Bool {
        self.trimmedBio.count <= self.bioMax
    }

    var bioRemaining: Int {
        self.bioMax - self.trimmedBio.count
    }

    /// True when neither cooldown-gated field has moved. The bio is excluded on
    /// purpose — it is what this is used to permit.
    var identityUnchanged: Bool {
        self.trimmedHandle == self.originalHandle
            && self.trimmedDisplayName == self.originalDisplayName
    }

    /// The cooldown freezes the byline, not the whole form. A bio rewrites no
    /// published attribution, so a bio-only edit stays submittable even while
    /// the handle and display name are locked — which matches the server, where
    /// `isRename` compares only those two fields.
    var canSubmit: Bool {
        guard !self.isSaving, self.handleIsValid, self.displayNameIsValid, self.bioIsValid
        else { return false }
        return self.isEditable || self.identityUnchanged
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
                avatar: self.avatar,
                bio: self.trimmedBio
            )
            _ = try await self.repo.setPublicAuthorIdentity(payload)
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}

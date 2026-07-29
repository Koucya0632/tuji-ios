// Pins the 公開作者身分 rules — the consent step that stands between a private
// profile and the community wall.
//
// Two things these tests protect. First, the handle shape: the author route is
// `/api/atlas/public/authors/{handle}`, so anything needing URL escaping must
// be rejected before it becomes an unreachable profile. Second, that a blank
// display name can never be submitted — the old code fell back to the handle,
// which used to be the first half of the user's email address.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct PublicAuthorIdentityVMTests {
    private func identity(
        confirmed: Bool = false,
        handle: String = "tuji-8f3a2c1d9b4e",
        displayName: String = "",
        canChange: Bool? = nil,
        nextChangeAt: String? = nil
    )
        -> PublicAuthorIdentity
    {
        PublicAuthorIdentity(
            confirmed: confirmed,
            handle: handle,
            displayName: displayName,
            avatar: "face",
            canChange: canChange,
            nextChangeAt: nextChangeAt
        )
    }

    private func vm(
        _ identity: PublicAuthorIdentity,
        repo: FakePublicAuthorIdentityEditing = FakePublicAuthorIdentityEditing()
    )
        -> PublicAuthorIdentityVM
    {
        PublicAuthorIdentityVM(identity: identity, repo: repo)
    }

    // MARK: - Validation

    @Test
    func aBlankDisplayNameBlocksSubmission() {
        let model = self.vm(self.identity())
        #expect(model.canSubmit == false)
        model.displayName = "   "
        #expect(model.canSubmit == false)
        model.displayName = "Mika"
        #expect(model.canSubmit)
    }

    @Test
    func displayNameIsCappedAtTwentyCharacters() {
        let model = self.vm(self.identity())
        model.displayName = String(repeating: "あ", count: PublicAuthorIdentityVM.displayNameMax)
        #expect(model.canSubmit)
        model.displayName += "あ"
        #expect(model.canSubmit == false)
    }

    /// Every rejected handle here would produce an author link that 404s.
    @Test
    func handlesMustSurviveBeingAPathComponent() {
        let model = self.vm(self.identity(), repo: FakePublicAuthorIdentityEditing())
        model.displayName = "Mika"

        for good in ["mika_k", "tuji-8f3a2c1d9b4e", "a.b-c_d", "ab"] {
            model.handle = good
            #expect(model.canSubmit, "expected \(good) to be accepted")
        }
        for bad in ["", "a", "mika k", "mika/k", "miká", String(repeating: "a", count: 41)] {
            model.handle = bad
            #expect(model.canSubmit == false, "expected \(bad) to be rejected")
        }
    }

    @Test
    func surroundingWhitespaceIsTrimmedRatherThanRejected() async {
        let repo = FakePublicAuthorIdentityEditing()
        let model = self.vm(self.identity(), repo: repo)
        model.handle = "  mika_k  "
        model.displayName = "  Mika  "
        #expect(model.canSubmit)
        #expect(await model.save())
        #expect(repo.saved?.handle == "mika_k")
        #expect(repo.saved?.displayName == "Mika")
    }

    // MARK: - Consent state

    @Test
    func anUnconfirmedIdentityIsTreatedAsFirstTime() {
        #expect(self.vm(self.identity(confirmed: false)).isFirstTime)
        #expect(self.vm(self.identity(confirmed: true, displayName: "Mika")).isFirstTime == false)
    }

    // MARK: - Save

    @Test
    func aFailedSaveSurfacesTheServerMessageAndDoesNotProceed() async {
        let repo = FakePublicAuthorIdentityEditing()
        repo.saveError = APIError.server(status: 409, body: "handle_taken")
        let model = self.vm(self.identity(), repo: repo)
        model.displayName = "Mika"
        model.handle = "mika_k"

        #expect(await model.save() == false)
        #expect(model.errorMessage != nil)
    }

    @Test
    func savingIsRefusedWhileTheFormIsInvalid() async {
        let repo = FakePublicAuthorIdentityEditing()
        let model = self.vm(self.identity(), repo: repo)
        #expect(await model.save() == false)
        #expect(repo.saved == nil)
    }

    // MARK: - Rename cooldown

    // A rename rewrites the byline on everything the author already published,
    // so it is limited once they have public content.

    @Test
    func aRunningCooldownLocksTheFormBeforeAnythingIsTyped() async {
        let repo = FakePublicAuthorIdentityEditing()
        let model = self.vm(
            self.identity(
                confirmed: true,
                displayName: "Mika",
                canChange: false,
                nextChangeAt: "2026-08-28T00:00:00.000Z"
            ),
            repo: repo
        )
        #expect(model.isEditable == false)
        #expect(model.canSubmit == false)
        #expect(model.nextChangeText != nil)

        // And the form cannot be submitted around the lock.
        model.displayName = "Ad Ad Ad"
        #expect(model.canSubmit == false)
        #expect(await model.save() == false)
        #expect(repo.saved == nil)
    }

    /// A payload without the field must not lock someone out of their own form.
    @Test
    func aMissingCooldownFieldMeansEditable() {
        let model = self.vm(self.identity(canChange: nil))
        #expect(model.isEditable)
        #expect(model.nextChangeText == nil)
    }

    @Test
    func anExpiredCooldownLeavesTheFormOpen() {
        let model = self.vm(self.identity(confirmed: true, displayName: "Mika", canChange: true))
        #expect(model.isEditable)
        model.handle = "mika_k"
        #expect(model.canSubmit)
    }
}

// MARK: - Gate

@MainActor
struct PublicAuthorGateTests {
    @Test
    func aConfirmedIdentityLetsPublishingThrough() async {
        let repo = FakePublicAuthorIdentityEditing()
        repo.identity = PublicAuthorIdentity(
            confirmed: true,
            handle: "mika_k",
            displayName: "Mika",
            avatar: "face",
            canChange: true,
            nextChangeAt: nil
        )
        #expect(await PublicAuthorGate(repo: repo).identityNeedingConfirmation() == nil)
    }

    @Test
    func anUnconfirmedIdentityIsHandedBackToSeedTheSheet() async {
        let repo = FakePublicAuthorIdentityEditing()
        let pending = await PublicAuthorGate(repo: repo).identityNeedingConfirmation()
        #expect(pending?.handle == "tuji-000000000000")
    }

    /// Fails open: the server enforces the gate anyway (409), and showing the
    /// consent screen because one request dropped reads as the app forgetting
    /// that the user already agreed.
    @Test
    func aFailedLookupDoesNotBlockPublishing() async {
        let repo = FakePublicAuthorIdentityEditing()
        repo.loadError = APIError.transport(URLError(.notConnectedToInternet))
        #expect(await PublicAuthorGate(repo: repo).identityNeedingConfirmation() == nil)
    }

    @Test
    func onlyTheIdentityConflictIsRecognisedAsFixable() {
        #expect(PublicAuthorGate.isIdentityRequired(APIError.server(status: 409, body: nil)))
        #expect(PublicAuthorGate.isIdentityRequired(APIError.server(status: 500, body: nil)) == false)
        #expect(PublicAuthorGate.isIdentityRequired(APIError.forbidden) == false)
        #expect(PublicAuthorGate.isIdentityRequired(URLError(.badURL)) == false)
    }
}

// MARK: - Fake

@MainActor
final class FakePublicAuthorIdentityEditing: PublicAuthorIdentityEditing {
    var identity = PublicAuthorIdentity(
        confirmed: false,
        handle: "tuji-000000000000",
        displayName: "",
        avatar: "face",
        canChange: true,
        nextChangeAt: nil
    )
    var loadError: Error?
    var saveError: Error?
    private(set) var saved: PublicAuthorIdentityPayload?

    func publicAuthorIdentity() async throws -> PublicAuthorIdentity {
        if let loadError { throw loadError }
        return self.identity
    }

    func setPublicAuthorIdentity(
        _ payload: PublicAuthorIdentityPayload
    ) async throws
        -> PublicAuthorIdentityResponse
    {
        if let saveError { throw saveError }
        self.saved = payload
        return PublicAuthorIdentityResponse(
            ok: true,
            confirmed: true,
            handle: payload.handle,
            displayName: payload.displayName
        )
    }
}

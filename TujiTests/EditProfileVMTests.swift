// Pins 編輯個人資料's form rules — what makes it dirty, when 儲存 is live, and
// what a save actually sends.
//
// None of this was reachable before: the whole form lived on the `View` and its
// `profiles` dependency was a hardcoded `private let ... = .shared` with no
// init seam, so no fake could be substituted even from inside the module. The
// seeding rules were the exception, because someone had already lifted
// `profileSeed` out as a `static func` — those tests live in
// SessionUserMirrorTests and now point at the view model.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct EditProfileVMTests {
    private func author(displayName: String, handle: String = "TJ00000042") -> AtlasAuthor {
        AtlasAuthor(
            handle: handle,
            displayName: displayName,
            avatar: "face",
            bio: nil,
            joinedAt: nil,
            publishedCount: 0,
            saveCount: 0
        )
    }

    private func me(nickname: String?, bio: String? = nil) -> UserMeUser {
        UserMeUser(
            id: UUID().uuidString,
            email: "mika@example.com",
            username: "TJ00000042",
            nickname: nickname,
            avatar: "face",
            bio: bio
        )
    }

    @Test("a freshly loaded profile is not dirty")
    func loadedProfileIsClean() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika", bio: "hi"))
        let vm = EditProfileVM(profiles: fake)

        await vm.load(session: nil)

        #expect(!vm.dirty)
        #expect(!vm.canSave)
        #expect(vm.serverUid == "TJ00000042")
    }

    @Test("editing the nickname makes the form dirty and 儲存 live")
    func editingMakesItDirty() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)

        vm.nickname = "Mika 2"

        #expect(vm.dirty)
        #expect(vm.canSave)
    }

    @Test("whitespace-only edits are not edits")
    func whitespaceIsNotAChange() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)

        vm.nickname = "  Mika  "

        #expect(!vm.dirty, "trailing spaces must not arm 儲存")
    }

    @Test("an over-long nickname blocks saving without blocking typing")
    func overLongNicknameBlocksSave() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)

        vm.nickname = String(repeating: "あ", count: EditProfileVM.nicknameMax + 1)

        #expect(vm.dirty)
        #expect(!vm.nicknameIsValid)
        #expect(!vm.canSave)
    }

    @Test("a staged photo makes the form dirty on its own")
    func stagedAvatarIsAChange() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)

        vm.stageAvatar(data: Data([0x01]))

        #expect(vm.dirty)
        #expect(vm.hasCustomAvatar)
    }

    @Test("choosing the default mascot discards a staged photo")
    func defaultAvatarClearsTheStagedPhoto() async {
        // Otherwise the pending bytes would win at save time and silently undo
        // the choice the user just made.
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)
        vm.stageAvatar(data: Data([0x01]))

        vm.useDefaultAvatar()

        #expect(!vm.hasCustomAvatar)
    }

    @Test("an empty nickname is sent as nil, not as an empty string")
    func emptyNicknameIsSentAsNil() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)
        vm.nickname = "   "

        _ = await vm.save()

        #expect(fake.sent?.nickname == nil)
    }

    @Test("a staged photo travels as data, never alongside a stale avatar string")
    func stagedPhotoSuppressesTheAvatarString() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)
        vm.stageAvatar(data: Data([0x01]))

        _ = await vm.save()

        #expect(fake.sentAvatarData != nil)
        #expect(fake.sent?.avatar == nil, "a URL alongside the bytes would contradict them")
    }

    @Test("a display name equal to the UID means no nickname")
    func uidDisplayNameMeansNoNickname() async {
        let fake = FakeProfileEditing(me: self.me(nickname: nil))
        fake.result = .success(self.author(displayName: "TJ00000042"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)
        vm.bio = "hi"

        let saved = await vm.save()

        #expect(saved?.nickname == nil, "the UID fallback is not a nickname to mirror")
    }

    @Test("a failed save surfaces the error and does not report success")
    func failedSaveReportsNothingToMirror() async {
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        fake.result = .failure(ProfileFakeError.boom)
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)
        vm.nickname = "Mika 2"

        let saved = await vm.save()

        #expect(saved == nil, "the screen must not dismiss on a failed save")
        #expect(vm.error != nil)
        #expect(!vm.saving)
    }

    @Test("a second load does not clobber edits made after the first")
    func reloadDoesNotClobberEdits() async {
        // `.task` can re-fire; the guard on `loading` is what stops a re-entry
        // from resetting the field the user is typing in.
        let fake = FakeProfileEditing(me: self.me(nickname: "Mika"))
        let vm = EditProfileVM(profiles: fake)
        await vm.load(session: nil)
        vm.nickname = "Mika 2"

        await vm.load(session: nil)

        #expect(vm.nickname == "Mika 2")
    }
}

private enum ProfileFakeError: Error { case boom }

@MainActor
private final class FakeProfileEditing: ProfileEditing {
    var me: UserMeUser
    var result: Result<AtlasAuthor, Error>
    private(set) var sent: ProfileEditChange?
    private(set) var sentAvatarData: Data?

    init(me: UserMeUser) {
        self.me = me
        self.result = .success(
            AtlasAuthor(
                handle: "TJ00000042",
                displayName: "Mika",
                avatar: "face",
                bio: nil,
                joinedAt: nil,
                publishedCount: 0,
                saveCount: 0
            )
        )
    }

    func load() async throws -> UserMeUser? {
        self.me
    }

    func edit(_ change: ProfileEditChange, avatarData: Data?) async throws -> AtlasAuthor {
        self.sent = change
        self.sentAvatarData = avatarData
        return try self.result.get()
    }
}

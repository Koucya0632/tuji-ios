// 個人筆記 on the client: when the note area shows and in which form, and what
// the store does with saves and deletes. Decisions only — no copy asserted.

import Foundation
import Testing
@testable import Tuji

@MainActor
private final class FakeWordNoteRepository: WordNoteRepository {
    var response = WordNotesResponse(available: true, canWrite: true, maxLength: 500, notes: [])
    var failNext: Error?
    private(set) var loads = 0

    private func maybeFail() throws {
        if let error = self.failNext {
            self.failNext = nil
            throw error
        }
    }

    func notes() async throws -> WordNotesResponse {
        self.loads += 1
        try self.maybeFail()
        return self.response
    }

    func save(wordId: String, body: String) async throws -> WordNote {
        try self.maybeFail()
        return WordNote(wordId: wordId, body: body, updatedAt: "2026-09-28T00:00:00Z")
    }

    func delete(wordId _: String) async throws {
        try self.maybeFail()
    }
}

private func note(_ id: String, _ body: String = "記法") -> WordNote {
    WordNote(wordId: id, body: body, updatedAt: "2026-09-28T00:00:00Z")
}

@MainActor
struct WordNotesStoreTests {
    @Test
    func readsOnceAndServesEveryWordFromMemory() async {
        let repo = FakeWordNoteRepository()
        repo.response = WordNotesResponse(available: true, canWrite: true, maxLength: 500, notes: [note("apple")])
        let store = WordNotesStore(repository: repo)
        await store.loadIfNeeded()
        await store.loadIfNeeded()
        #expect(repo.loads == 1)
        #expect(store.note(for: "apple")?.body == "記法")
        #expect(store.note(for: "banana") == nil)
    }

    @Test
    func aFailedLoadIsRetriedNextTime() async {
        let repo = FakeWordNoteRepository()
        repo.failNext = APIError.server(status: 500, body: nil)
        let store = WordNotesStore(repository: repo)
        await store.loadIfNeeded()
        #expect(store.phase == .failed)
        await store.loadIfNeeded()
        #expect(repo.loads == 2)
        #expect(store.phase == .loaded)
    }

    @Test
    func savingTrimsAndStores() async {
        let store = WordNotesStore(repository: FakeWordNoteRepository())
        await store.loadIfNeeded()
        let outcome = await store.save("  跟 cup 分開記  ", for: "mug")
        #expect(outcome == .done)
        #expect(store.note(for: "mug")?.body == "跟 cup 分開記")
    }

    @Test
    func aNonMemberSavingIsSentToThePaywall() async {
        let repo = FakeWordNoteRepository()
        let store = WordNotesStore(repository: repo)
        await store.loadIfNeeded()
        repo.failNext = APIError.paymentRequired(message: nil)
        let outcome = await store.save("x", for: "mug")
        #expect(outcome == .needsUpgrade)
        #expect(store.note(for: "mug") == nil)
    }

    @Test
    func aRefusedDeletePutsTheNoteBack() async {
        let repo = FakeWordNoteRepository()
        repo.response = WordNotesResponse(available: true, canWrite: false, maxLength: 500, notes: [note("apple")])
        let store = WordNotesStore(repository: repo)
        await store.loadIfNeeded()
        repo.failNext = APIError.server(status: 500, body: nil)
        _ = await store.delete(for: "apple")
        #expect(store.note(for: "apple") != nil)
    }

    @Test
    func validityFollowsTheServerLimitAfterTrimming() async {
        let store = WordNotesStore(repository: FakeWordNoteRepository())
        await store.loadIfNeeded()
        #expect(store.isValid(" a "))
        #expect(!store.isValid("  \n "))
        #expect(store.isValid(String(repeating: "字", count: 500)))
        #expect(!store.isValid(String(repeating: "字", count: 501)))
    }

    @Test
    func signOutForgetsEverything() async {
        let repo = FakeWordNoteRepository()
        repo.response = WordNotesResponse(available: true, canWrite: true, maxLength: 500, notes: [note("apple")])
        let store = WordNotesStore(repository: repo)
        await store.loadIfNeeded()
        store.reset()
        #expect(store.note(for: "apple") == nil)
        await store.loadIfNeeded()
        #expect(repo.loads == 2)
    }
}

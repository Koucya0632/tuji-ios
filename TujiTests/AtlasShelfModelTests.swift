// Pins the 圖鑑管理 shelf: the learning-direction filter, the shelf state
// (including the `failed` case a failed sync used to render as 「還沒有卡片」),
// the selection reconcile a direction switch needs, and the batch delete that
// used to abort on its first failure and then hide the remainder.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AtlasShelfModelTests {
    private func store(
        images: [AtlasImageSummary],
        items: [AtlasItem],
        fake: FakeAtlasAuthoring = FakeAtlasAuthoring()
    ) async
        -> (AtlasStore, FakeAtlasAuthoring)
    {
        fake.syncResponse = AtlasFixtures.syncResponse(images: images, items: items)
        let store = AtlasStore(repository: fake)
        await store.sync(.full)
        return (store, fake)
    }

    // MARK: - Rows

    @Test
    func rowsKeepOnlyTheCurrentDirectionAndCountTheRest() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("ja"), AtlasFixtures.image("en")],
            items: [
                AtlasFixtures.item("t-ja", imageId: "ja", language: .ja),
                AtlasFixtures.item("t-en", imageId: "en", language: .en)
            ]
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        #expect(model.rows.map(\.id) == ["ja"])
        #expect(model.hiddenCount == 1)

        model.targetLanguage = .en

        #expect(model.rows.map(\.id) == ["en"])
        #expect(model.hiddenCount == 1)
    }

    /// An image with no confirmed item carries no language yet, so it must stay
    /// visible in both directions rather than vanish until the pipeline lands.
    @Test
    func capturesWithNoItemYetStayVisibleInEitherDirection() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("pending", status: "processing")],
            items: []
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        #expect(model.rows.map(\.id) == ["pending"])
        model.targetLanguage = .en
        #expect(model.rows.map(\.id) == ["pending"])
        #expect(model.hiddenCount == 0)
    }

    @Test
    func rowTitleIsTheLemmaOnceThereIsOneAndTheStatusFallbackUntilThen() async throws {
        let (store, _) = await self.store(
            images: [
                AtlasFixtures.image("done"),
                AtlasFixtures.image("pending", status: "processing")
            ],
            items: [AtlasFixtures.item("t1", imageId: "done", lemma: "ねこ")]
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        let done = try #require(model.rows.first { $0.id == "done" })
        let pending = try #require(model.rows.first { $0.id == "pending" })

        #expect(done.title == "ねこ")
        #expect(done.subtitle == "中文-t1")
        // 未完成 next to 已完成 was the contradiction; the fallback now comes
        // from the same status the chip shows.
        #expect(pending.title == pending.image.placeholderTitle)
        #expect(pending.subtitle == nil)
    }

    // MARK: - State

    @Test
    func aFailedSyncReadsAsFailedNotAsAnEmptyShelf() async {
        let fake = FakeAtlasAuthoring()
        fake.syncError = AtlasFakeError.boom
        let store = AtlasStore(repository: fake)
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        await model.load()

        #expect(model.state == .failed)
    }

    @Test
    func anEmptyAccountReadsAsEmpty() async {
        let (store, _) = await self.store(images: [], items: [])
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        #expect(model.state == .empty)
        #expect(!model.canSelect)
    }

    @Test
    func everythingInTheOtherDirectionReadsAsHiddenElsewhere() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("en")],
            items: [AtlasFixtures.item("t-en", imageId: "en", language: .en)]
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        #expect(model.state == .hiddenElsewhere(count: 1))
    }

    @Test
    func rowsPresentReadsAsLoaded() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("i1")],
            items: [AtlasFixtures.item("t1", imageId: "i1")]
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)

        #expect(model.state == .loaded)
        #expect(model.canSelect)
    }

    // MARK: - Selection

    /// The bug: 「刪除 N 張卡片」 counted — and deleted — rows that the direction
    /// switch had taken off screen.
    @Test
    func switchingDirectionDropsSelectionsThatWentOffScreen() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("ja"), AtlasFixtures.image("en")],
            items: [
                AtlasFixtures.item("t-ja", imageId: "ja", language: .ja),
                AtlasFixtures.item("t-en", imageId: "en", language: .en)
            ]
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)
        model.setSelecting(true)
        model.toggleSelection("ja")
        #expect(model.selectedIds == ["ja"])

        model.targetLanguage = .en

        #expect(model.selectedIds.isEmpty)
    }

    @Test
    func leavingSelectionModeClearsTheSelection() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("i1")],
            items: [AtlasFixtures.item("t1", imageId: "i1")]
        )
        let model = AtlasShelfModel(store: store, targetLanguage: .ja)
        model.setSelecting(true)
        model.toggleSelection("i1")

        model.setSelecting(false)

        #expect(model.selectedIds.isEmpty)
        #expect(!model.isSelecting)
    }

    // MARK: - Delete

    @Test
    func deleteRemovesEveryIdAndReportsTheMutationOnce() async {
        let (store, fake) = await self.store(
            images: [AtlasFixtures.image("a"), AtlasFixtures.image("b")],
            items: []
        )
        let spy = SpyAtlasMutationRefreshing()
        let model = AtlasShelfModel(store: store, mutations: spy, targetLanguage: .ja)
        model.setSelecting(true)
        model.toggleSelection("a")
        model.toggleSelection("b")

        await model.delete(["a", "b"])

        #expect(Set(fake.deletedIds) == ["a", "b"])
        #expect(model.selectedIds.isEmpty)
        #expect(!model.isSelecting)
        #expect(model.errorMessage == nil)
        #expect(spy.reported == [.itemsDeleted])
    }

    /// The old path aborted on the first failure and then cleared the selection,
    /// so the undeleted remainder was invisible and unretryable.
    @Test
    func aPartlyFailedBatchDeletesTheRestAndKeepsTheFailuresSelected() async {
        let fake = FakeAtlasAuthoring()
        fake.deleteFailures = ["b"]
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("a"), AtlasFixtures.image("b"), AtlasFixtures.image("c")],
            items: [],
            fake: fake
        )
        let spy = SpyAtlasMutationRefreshing()
        let model = AtlasShelfModel(store: store, mutations: spy, targetLanguage: .ja)
        model.setSelecting(true)

        await model.delete(["a", "b", "c"])

        #expect(Set(fake.deletedIds) == ["a", "c"])
        #expect(model.selectedIds == ["b"])
        #expect(model.isSelecting)
        #expect(model.errorMessage != nil)
        // Two rows did move, so the learning stores still need reconciling.
        #expect(spy.reported == [.itemsDeleted])
    }

    @Test
    func aFullyFailedBatchReportsNoMutation() async {
        let fake = FakeAtlasAuthoring()
        fake.deleteFailures = ["a"]
        let (store, _) = await self.store(images: [AtlasFixtures.image("a")], items: [], fake: fake)
        let spy = SpyAtlasMutationRefreshing()
        let model = AtlasShelfModel(store: store, mutations: spy, targetLanguage: .ja)

        await model.delete(["a"])

        #expect(spy.reported.isEmpty)
        #expect(model.errorMessage != nil)
    }

    // MARK: - 取消公開

    @Test
    func withdrawReportsTheMutationOnSuccessOnly() async {
        let fake = FakeAtlasAuthoring()
        let (store, _) = await self.store(images: [], items: [], fake: fake)
        let spy = SpyAtlasMutationRefreshing()
        let model = AtlasShelfModel(store: store, mutations: spy, targetLanguage: .ja)

        let ok = await model.withdraw(itemId: "t1", refreshing: spy)

        #expect(ok)
        #expect(fake.withdrawnIds == ["t1"])
        #expect(spy.reported == [.itemWithdrawn])
        #expect(!model.withdrawing)
    }

    @Test
    func aFailedWithdrawSurfacesTheErrorAndReportsNothing() async {
        let fake = FakeAtlasAuthoring()
        fake.withdrawError = AtlasFakeError.boom
        let (store, _) = await self.store(images: [], items: [], fake: fake)
        let spy = SpyAtlasMutationRefreshing()
        let model = AtlasShelfModel(store: store, mutations: spy, targetLanguage: .ja)

        let ok = await model.withdraw(itemId: "t1", refreshing: spy)

        #expect(!ok)
        #expect(model.errorMessage != nil)
        #expect(spy.reported.isEmpty)
        #expect(!model.withdrawing)
    }

    // MARK: - Scoping

    /// A `@State` model is built before SwiftUI can hand it the environment, so
    /// there is a moment when it does not know 當前圖鑑語言. It used to answer
    /// `.ja` in that moment, which filtered an 英文 learner's own cards against
    /// the language they are not learning. Showing nothing for a frame is the
    /// honest answer; `loading`, not `empty`, is what says so.
    @Test
    func anUnscopedShelfShowsNothingRatherThanGuessingADirection() async {
        let (store, _) = await self.store(
            images: [AtlasFixtures.image("en")],
            items: [AtlasFixtures.item("t-en", imageId: "en", language: .en)]
        )
        let model = AtlasShelfModel(store: store)

        #expect(model.targetLanguage == nil)
        #expect(model.rows.isEmpty)
        #expect(model.state == .loading)
        #expect(!model.canSelect)

        model.targetLanguage = .en

        #expect(model.rows.map(\.id) == ["en"])
        #expect(model.state == .loaded)
    }
}

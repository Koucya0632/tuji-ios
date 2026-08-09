// Pins AtlasPublicDetailVM's consumption action state behind the AtlasItemConsuming
// seam: save reflects the response, a failed unsave must NOT flip the toggle
// (the state machine's one real hazard).

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AtlasPublicDetailVMTests {
    private func item(slug: String = "s1") -> AtlasPublicItem {
        AtlasPublicItem(
            id: "i1",
            slug: slug,
            lemma: "cup",
            displayZhHant: "杯子",
            targetLanguage: .en,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
    }

    @Test
    func saveReflectsResponseAndReturnsSaved() async {
        let fake = FakeItemConsuming()
        fake.saveResult = .success(AtlasSaveResponse(ok: true, saved: true, saveCount: 5))
        let refresher = RecordingCommunityLearningRefresher()
        let vm = AtlasPublicDetailVM(
            item: self.item(),
            repo: fake,
            learningRefresher: refresher
        )

        let result = await vm.toggleSave()

        #expect(result == true)
        #expect(vm.saved)
        #expect(vm.saveCount == 5)
        #expect(vm.actionError == nil)
        #expect(!vm.busy)
        #expect(refresher.refreshCount == 1)
    }

    @Test
    func successfulSaveRefreshesCommunityWordsBeforeReturning() async {
        let fake = FakeItemConsuming()
        let refresher = RecordingCommunityLearningRefresher()
        let vm = AtlasPublicDetailVM(
            item: self.item(),
            repo: fake,
            learningRefresher: refresher
        )

        let result = await vm.toggleSave()

        #expect(result == true)
        #expect(refresher.refreshCount == 1)
    }

    @Test
    func successfulUnsaveRunsTheSameLearningRefreshPolicy() async {
        let fake = FakeItemConsuming()
        let refresher = RecordingCommunityLearningRefresher()
        let vm = AtlasPublicDetailVM(
            item: self.item(),
            repo: fake,
            learningRefresher: refresher
        )

        _ = await vm.toggleSave()
        let result = await vm.toggleSave()

        #expect(result == false)
        #expect(!vm.saved)
        #expect(refresher.refreshCount == 2)
    }

    @Test
    func reopeningLoadsExistingSaveState() async {
        let fake = FakeItemConsuming()
        fake.saveStateResult = .success(AtlasSaveResponse(ok: true, saved: true, saveCount: 5))
        let vm = AtlasPublicDetailVM(item: self.item(), repo: fake)

        await vm.loadSaveState()

        #expect(vm.saved)
        #expect(vm.saveCount == 5)
        #expect(fake.loadedSlugs == ["s1"])
    }

    @Test
    func failedUnsaveKeepsSavedStateAndSurfacesError() async {
        let fake = FakeItemConsuming()
        fake.saveResult = .success(AtlasSaveResponse(ok: true, saved: true, saveCount: 1))
        let refresher = RecordingCommunityLearningRefresher()
        let vm = AtlasPublicDetailVM(
            item: self.item(),
            repo: fake,
            learningRefresher: refresher
        )
        _ = await vm.toggleSave() // now saved

        // The next toggle is an unsave; make it fail — the toggle must not flip.
        fake.unsaveResult = .failure(FakeError.boom)
        let result = await vm.toggleSave()

        #expect(result == nil)
        #expect(vm.saved)
        #expect(vm.actionError != nil)
        #expect(!vm.busy)
        #expect(refresher.refreshCount == 1)
    }

    // 檢舉 moved to ReportFlow (see ReportFlowTests) — these two tests moved
    // with it, and now cover all three targets instead of only the item.

    @Test
    func openingDetailReplacesTheFeedPreview() async {
        let preview = self.item(slug: "s1")
        let detailed = AtlasPublicItem(
            id: "i1",
            slug: "s1",
            lemma: "detailed cup",
            displayZhHant: "杯子",
            targetLanguage: .en,
            category: nil,
            imageUrl: nil,
            author: nil,
            publishedAt: nil
        )
        let reader = FakePublicItemsReading(item: detailed)
        let vm = AtlasPublicDetailVM(
            item: preview,
            repo: FakeItemConsuming(),
            itemReader: reader
        )

        await vm.loadDetail()

        #expect(vm.item.lemma == "detailed cup")
        #expect(reader.loadedSlugs == ["s1"])
    }
}

@MainActor
private final class RecordingCommunityLearningRefresher: CommunityLearningRefreshing {
    private(set) var refreshCount = 0

    func refreshAfterLearningMutation() async {
        self.refreshCount += 1
    }
}

private enum FakeError: Error { case boom }

@MainActor
private final class FakeItemConsuming: AtlasItemConsuming {
    var saveStateResult: Result<AtlasSaveResponse, Error> = .success(AtlasSaveResponse(
        ok: true,
        saved: false,
        saveCount: 0
    ))
    var saveResult: Result<AtlasSaveResponse, Error> = .success(AtlasSaveResponse(ok: true, saved: true, saveCount: 1))
    var unsaveResult: Result<AtlasSaveResponse, Error> = .success(AtlasSaveResponse(
        ok: true,
        saved: false,
        saveCount: 0
    ))
    var reportResult: Result<Void, Error> = .success(())
    private(set) var loadedSlugs: [String] = []
    private(set) var reportedSlugs: [String] = []

    func saveState(slug: String) async throws -> AtlasSaveResponse {
        self.loadedSlugs.append(slug)
        return try self.saveStateResult.get()
    }

    func save(slug _: String) async throws -> AtlasSaveResponse {
        try self.saveResult.get()
    }

    func unsave(slug _: String) async throws -> AtlasSaveResponse {
        try self.unsaveResult.get()
    }

    func report(slug: String, reason _: AtlasReportReason, detail _: String?) async throws {
        self.reportedSlugs.append(slug)
        try self.reportResult.get()
    }
}

@MainActor
private final class FakePublicItemsReading: PublicItemsReading {
    let item: AtlasPublicItem
    private(set) var loadedSlugs: [String] = []

    init(item: AtlasPublicItem) {
        self.item = item
    }

    func publicItems(
        lemma _: String,
        language _: TargetLanguage,
        limit _: Int
    ) async throws
        -> [AtlasPublicItem]
    {
        [self.item]
    }

    func publicItem(slug: String) async throws -> AtlasPublicItem {
        self.loadedSlugs.append(slug)
        return self.item
    }
}

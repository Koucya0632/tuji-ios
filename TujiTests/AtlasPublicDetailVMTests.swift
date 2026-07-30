// Pins AtlasPublicDetailVM's consumption action state behind the AtlasItemConsuming
// seam: save reflects the response, a failed unsave must NOT flip the toggle
// (the state machine's one real hazard), and report sets/gates its flag.

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
        let vm = AtlasPublicDetailVM(item: self.item(), repo: fake)

        let result = await vm.toggleSave()

        #expect(result == true)
        #expect(vm.saved)
        #expect(vm.saveCount == 5)
        #expect(vm.actionError == nil)
        #expect(!vm.busy)
    }

    @Test
    func successfulSaveRefreshesCommunityWordsBeforeReturning() async {
        let fake = FakeItemConsuming()
        var refreshCount = 0
        let vm = AtlasPublicDetailVM(item: self.item(), repo: fake) {
            refreshCount += 1
        }

        let result = await vm.toggleSave()

        #expect(result == true)
        #expect(refreshCount == 1)
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
        let vm = AtlasPublicDetailVM(item: self.item(), repo: fake)
        _ = await vm.toggleSave() // now saved

        // The next toggle is an unsave; make it fail — the toggle must not flip.
        fake.unsaveResult = .failure(FakeError.boom)
        let result = await vm.toggleSave()

        #expect(result == nil)
        #expect(vm.saved)
        #expect(vm.actionError != nil)
        #expect(!vm.busy)
    }

    @Test
    func reportSuccessSetsSentFlag() async {
        let fake = FakeItemConsuming()
        let vm = AtlasPublicDetailVM(item: self.item(slug: "s9"), repo: fake)

        await vm.report(.spam)

        #expect(vm.reportSent)
        #expect(fake.reportedSlugs == ["s9"])
    }

    @Test
    func reportFailureSurfacesErrorAndLeavesSentFalse() async {
        let fake = FakeItemConsuming()
        fake.reportResult = .failure(FakeError.boom)
        let vm = AtlasPublicDetailVM(item: self.item(), repo: fake)

        await vm.report(.spam)

        #expect(!vm.reportSent)
        #expect(vm.actionError != nil)
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

// Shared 自製圖鑑 fixtures + the AtlasAuthoring fake. The seam existed before
// this file did, but `AtlasStore.init` was private, so nothing could stand a
// store up over a fake; unsealing it is what made AtlasStoreTests and
// AtlasShelfModelTests possible.

import Foundation
@testable import Tuji

enum AtlasFixtures {
    static func image(
        _ id: String,
        status: String = "cards_ready",
        updatedAt: String? = "2026-01-01T00:00:00Z",
        deletedAt: String? = nil
    )
        -> AtlasImageSummary
    {
        AtlasImageSummary(
            id: id,
            status: status,
            width: nil,
            height: nil,
            createdAt: nil,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            imageUrl: nil,
            thumbUrl: nil
        )
    }

    static func item(
        _ id: String,
        imageId: String,
        language: TargetLanguage = .ja,
        lemma: String? = nil,
        updatedAt: String? = "2026-01-01T00:00:00Z",
        deletedAt: String? = nil,
        reviewStatus: String? = nil
    )
        -> AtlasItem
    {
        AtlasItem(
            id: id,
            imageId: imageId,
            targetLanguage: language,
            canonicalWordId: nil,
            primaryLabel: "primary",
            fineLabel: nil,
            lemma: lemma ?? "lemma-\(id)",
            displayZhHant: "中文-\(id)",
            partOfSpeech: nil,
            cefrLevel: nil,
            pronunciation: nil,
            reading: nil,
            category: nil,
            taxonomyPath: nil,
            definitionZhHant: nil,
            definitionTarget: nil,
            exampleTarget: nil,
            exampleZhHant: nil,
            noteZhHant: nil,
            visibility: nil,
            reviewStatus: reviewStatus,
            publicSlug: nil,
            createdAt: nil,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    static func syncResponse(
        images: [AtlasImageSummary] = [],
        items: [AtlasItem] = [],
        serverTime: String = "T1"
    )
        -> AtlasSyncResponse
    {
        AtlasSyncResponse(
            serverTime: serverTime,
            images: images,
            items: items,
            cards: [],
            cardStates: [],
            mastery: [],
            paging: AtlasSyncPaging(limit: 500, truncated: false)
        )
    }

    static func entitlement(
        plan: String = "free",
        slots: Int = 1,
        slotsLimit: Int = 50
    )
        -> AtlasEntitlement
    {
        AtlasEntitlement(
            plan: plan,
            atlasSlotsLimit: slotsLimit,
            primaryAiSoftLimitMonthly: 30,
            precisionAiLimitMonthly: 0,
            subscriptionExpiresAt: nil,
            usage: AtlasUsage(atlasSlots: slots, primaryAiThisMonth: 0, precisionAiThisMonth: 0)
        )
    }

    /// `AtlasCandidate` declares its own `init(from:)` for the NUMERIC-as-string
    /// confidence, which suppresses the memberwise init — so a fixture has to go
    /// through the decoder the app uses.
    static func candidate(
        id: String = "c1",
        level: String = "primary",
        label: String = "cat",
        zhHant: String? = "貓",
        gloss: String? = nil,
        confidence: String = "0.9",
        rank: Int = 1
    ) throws
        -> AtlasCandidate
    {
        var fields = [
            "\"id\": \"\(id)\"",
            "\"level\": \"\(level)\"",
            "\"label\": \"\(label)\"",
            "\"normalizedLabel\": \"\(label)\"",
            "\"confidence\": \(confidence)",
            "\"rank\": \(rank)"
        ]
        if let zhHant { fields.append("\"zhHant\": \"\(zhHant)\"") }
        if let gloss { fields.append("\"gloss\": \"\(gloss)\"") }
        return try JSONDecoder().decode(
            AtlasCandidate.self,
            from: Data("{ \(fields.joined(separator: ", ")) }".utf8)
        )
    }

    static func uploadResponse(
        image: AtlasImageSummary? = nil,
        candidates: [AtlasCandidate]? = nil
    )
        -> AtlasUploadResponse
    {
        AtlasUploadResponse(
            duplicate: nil,
            targetLanguage: nil,
            image: image ?? Self.image("img-1", status: "uploaded"),
            job: nil,
            candidates: candidates
        )
    }

    static func payload(lemma: String = "cat") -> AtlasConfirmPayload {
        AtlasConfirmPayload(
            selectedCandidateId: nil,
            targetLanguage: nil,
            primaryLabel: lemma,
            fineLabel: nil,
            lemma: lemma,
            displayZhHant: "貓",
            displayGloss: nil,
            partOfSpeech: "noun",
            category: nil
        )
    }
}

/// `{ uiLang, learningDirection }` — the two-line stub the read seam exists for.
@MainActor
final class FakeLanguageContext: LanguageContext {
    var uiLang: String
    var learningDirection: LearningDirection

    init(uiLang: String = "zh-Hant", learningDirection: LearningDirection = .zhJa) {
        self.uiLang = uiLang
        self.learningDirection = learningDirection
    }
}

/// The 生成卡片 tail, in memory. Every method logs what it was asked for, so a
/// test can assert the checkpoint rule — that a resumed run never confirms twice.
@MainActor
final class FakeCardGenerating: AtlasCardGenerating {
    var item = AtlasFixtures.item("item-1", imageId: "img-1")
    /// How many more times each step should fail before succeeding. Counted
    /// rather than latched so a test can fail a run and then retry it.
    var confirmFailures = 0
    var generateFailures = 0
    var failureError: Error = AtlasFakeError.boom

    private(set) var confirmedImageIds: [String] = []
    private(set) var generatedItemIds: [String] = []
    private(set) var enrichedItemIds: [String] = []
    private(set) var reconciles = 0

    func confirm(imageId: String, payload _: AtlasConfirmPayload) async throws -> AtlasItem {
        if self.confirmFailures > 0 {
            self.confirmFailures -= 1
            throw self.failureError
        }
        self.confirmedImageIds.append(imageId)
        return self.item
    }

    func generateCards(forItem itemId: String) async throws {
        if self.generateFailures > 0 {
            self.generateFailures -= 1
            throw self.failureError
        }
        self.generatedItemIds.append(itemId)
    }

    func enrich(itemId: String) async throws {
        self.enrichedItemIds.append(itemId)
    }

    func reconcile() async {
        self.reconciles += 1
    }
}

/// The journal, in memory. Mirrors the file adapter's one subtlety: a save with
/// no thumbnail is a checkpoint and must not drop the frame already stored.
@MainActor
final class InMemoryCaptureJobJournal: CaptureJobJournal {
    private(set) var entries: [UUID: CaptureJobEntry] = [:]
    private(set) var saves: [CaptureJobRecord] = []

    init(_ preloaded: [CaptureJobEntry] = []) {
        for entry in preloaded {
            self.entries[entry.record.id] = entry
        }
    }

    func save(_ record: CaptureJobRecord, thumbnail: Data?) {
        self.saves.append(record)
        let existing = self.entries[record.id]?.thumbnail
        self.entries[record.id] = CaptureJobEntry(record: record, thumbnail: thumbnail ?? existing)
    }

    func remove(_ id: UUID) {
        self.entries[id] = nil
    }

    func restore() -> [CaptureJobEntry] {
        Array(self.entries.values)
    }

    func removeAll() {
        self.entries = [:]
    }
}

enum AtlasFakeError: Error {
    case boom
}

struct NotImplemented: Error {}

@MainActor
final class FakeAtlasAuthoring: AtlasAuthoring {
    var syncResponse = AtlasFixtures.syncResponse()
    var syncError: Error?
    var entitlementValue = AtlasFixtures.entitlement()
    /// ids whose delete should fail, so a batch can fail partway.
    var deleteFailures: Set<String> = []
    var withdrawError: Error?

    /// Every `since` the store has asked for — nil means "everything".
    private(set) var syncSinceLog: [String?] = []
    private(set) var deletedIds: [String] = []
    private(set) var withdrawnIds: [String] = []
    private(set) var entitlementFetches = 0

    /// Runs inside `deleteImage`, before it returns — lets a test land a
    /// sign-out (or another account's sync) in the middle of the call.
    var onDeleteImage: (() async -> Void)?

    // The capture half. These used to throw `NotImplemented`, which is exactly
    // how far the seam reached: `AtlasCaptureVM` was injectable and nothing
    // injected anything, so upload / 識別 / confirm went untested.
    var uploadResponse = AtlasFixtures.uploadResponse()
    var uploadError: Error?
    /// One canned answer per recognition depth, so a test can prove that
    /// re-tapping a mode does not spend a second call.
    var recognitionsByMode: [AtlasRecognitionMode: AtlasRecognitionResponse] = [:]
    var recognizeError: Error?

    private(set) var uploads = 0
    private(set) var recognizeCalls: [AtlasRecognitionMode] = []

    func sync(since: String?, limit _: Int) async throws -> AtlasSyncResponse {
        self.syncSinceLog.append(since)
        if let syncError { throw syncError }
        return self.syncResponse
    }

    func uploadImage(
        data _: Data,
        filename _: String,
        mimeType _: String,
        targetLanguage _: TargetLanguage?
    ) async throws
        -> AtlasUploadResponse
    {
        self.uploads += 1
        if let uploadError { throw uploadError }
        return self.uploadResponse
    }

    func recognize(imageId _: String, mode: AtlasRecognitionMode) async throws
        -> AtlasRecognitionResponse
    {
        self.recognizeCalls.append(mode)
        if let recognizeError { throw recognizeError }
        return self.recognitionsByMode[mode]
            ?? AtlasRecognitionResponse(job: nil, candidates: [])
    }

    func confirm(imageId _: String, payload _: AtlasConfirmPayload) async throws -> AtlasItem {
        throw NotImplemented()
    }

    func createCards(itemId _: String, cardTypes _: [String]) async throws -> [AtlasCard] {
        throw NotImplemented()
    }

    func deleteImage(id: String) async throws {
        await self.onDeleteImage?()
        if self.deleteFailures.contains(id) { throw AtlasFakeError.boom }
        self.deletedIds.append(id)
    }

    func enrich(itemId _: String) async throws {
        throw NotImplemented()
    }

    func detail(itemId _: String) async throws -> Word {
        throw NotImplemented()
    }

    func entitlement() async throws -> AtlasEntitlement {
        self.entitlementFetches += 1
        return self.entitlementValue
    }

    func withdraw(itemId: String) async throws -> AtlasWithdrawResponse {
        if let withdrawError { throw withdrawError }
        self.withdrawnIds.append(itemId)
        return AtlasWithdrawResponse(ok: true, reviewStatus: "withdrawn")
    }
}

/// Records what a mutation was reported as, without touching any store.
@MainActor
final class SpyAtlasMutationRefreshing: AtlasMutationRefreshing {
    private(set) var reported: [AtlasMutation] = []

    func refresh(after mutation: AtlasMutation) async {
        self.reported.append(mutation)
    }
}

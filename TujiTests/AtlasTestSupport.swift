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
        reviewStatus: String? = nil,
        displayJa: String? = nil,
        displayEn: String? = nil
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
            displayJa: displayJa,
            displayEn: displayEn,
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
        serverTime: String = "T1",
        lockedItemIds: [String]? = nil
    )
        -> AtlasSyncResponse
    {
        AtlasSyncResponse(
            serverTime: serverTime,
            images: images,
            items: items,
            lockedItemIds: lockedItemIds
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

/// The 生成卡片 tail, in memory. Every method logs what it was asked for.
@MainActor
final class FakeCardGenerating: AtlasCardGenerating {
    /// How many more times the step should fail before succeeding. Counted
    /// rather than latched so a test can fail a run and then retry it.
    var generateFailures = 0
    var failureError: Error = AtlasFakeError.boom

    private(set) var generatedItemIds: [String] = []
    private(set) var reconciles = 0

    func generateCards(forItem itemId: String) async throws {
        if self.generateFailures > 0 {
            self.generateFailures -= 1
            throw self.failureError
        }
        self.generatedItemIds.append(itemId)
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

    func sync(since: String?, limit _: Int) async throws -> AtlasSyncResponse {
        self.syncSinceLog.append(since)
        if let syncError { throw syncError }
        return self.syncResponse
    }

    func createCards(itemId _: String, cardTypes _: [String]) async throws -> [AtlasCard] {
        throw NotImplemented()
    }

    func deleteImage(id: String) async throws {
        await self.onDeleteImage?()
        if self.deleteFailures.contains(id) { throw AtlasFakeError.boom }
        self.deletedIds.append(id)
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

/// The 罐頭點數 confirm and fill-in, in memory. `fillIn` is what each poll of
/// the operation answers, in order; the last answer repeats.
@MainActor
final class FakeCreditConfirming: CreditCardConfirming {
    var itemId = "item-1"
    var confirmState = "pending"
    var fillIn: [String] = ["completed"]
    var confirmFailures = 0
    var failureError: Error = AtlasFakeError.boom

    private(set) var confirmed: [CreditConfirmRequest] = []
    private(set) var polls = 0

    func confirm(_ request: CreditConfirmRequest) async throws -> CreditConfirmed {
        if self.confirmFailures > 0 {
            self.confirmFailures -= 1
            throw self.failureError
        }
        self.confirmed.append(request)
        return CreditConfirmed(itemId: self.itemId, fulfillment: .init(self.confirmState))
    }

    func fulfillment(operationId _: String) async throws -> CreditOperation.Fulfillment {
        self.polls += 1
        return .init(self.fillIn.count > 1 ? self.fillIn.removeFirst() : self.fillIn.first ?? "completed")
    }
}

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

    static func entitlement(plan: String = "free", slots: Int = 1) -> AtlasEntitlement {
        AtlasEntitlement(
            plan: plan,
            atlasSlotsLimit: 50,
            primaryAiSoftLimitMonthly: 30,
            precisionAiLimitMonthly: 0,
            subscriptionExpiresAt: nil,
            usage: AtlasUsage(atlasSlots: slots, primaryAiThisMonth: 0, precisionAiThisMonth: 0)
        )
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

    func uploadImage(
        data _: Data,
        filename _: String,
        mimeType _: String,
        targetLanguage _: TargetLanguage?
    ) async throws
        -> AtlasUploadResponse
    {
        throw NotImplemented()
    }

    func recognize(imageId _: String, mode _: AtlasRecognitionMode) async throws
        -> AtlasRecognitionResponse
    {
        throw NotImplemented()
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

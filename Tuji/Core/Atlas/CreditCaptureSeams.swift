// The edges of 拍照新增's paid recognition, split from `CreditCaptureModel` so
// its rules — one upload per photo, never accept a price the user did not see,
// resend an uncertain accept under the same key — can be walked in a test.
//
// The model used to hold the concrete `APIClient` and reach `AuthService`,
// `UserDefaults`, `SettingsStore`, `AtlasStore` and `LiveAtlasRepository`
// statically; the only test that constructed one ran against all of them live.

import Foundation

/// 普通識別 or 高精度.
enum CreditCaptureMode: String {
    case primary, precision

    var feature: String {
        self == .primary ? "atlas.recognize.primary" : "atlas.recognize.precision"
    }

    init(feature: String) {
        self = feature == Self.precision.feature ? .precision : .primary
    }
}

/// An accept that was sent and not yet answered. Journalled before the request
/// leaves, so a relaunch resends the *same* key instead of charging twice.
struct PendingAccept: Codable, Equatable {
    let quoteId: String
    let key: String
}

/// The server, as the capture flow talks to it.
@MainActor
protocol CreditCaptureAPI {
    func catalog() async throws -> CreditCatalog
    func wallet() async throws -> CreditWallet
    func operations() async throws -> [CreditOperation]
    func image(id: String) async throws -> AtlasImageSummary
    /// Nothing leaves the phone before this: the photo is uploaded on 開始識別.
    func upload(photo: Data) async throws -> AtlasImageSummary
    /// `uiLanguage` is the interface the capture is made on. The server derives
    /// the rest from it — which gloss the run asks for, which field the form
    /// shows (`CreditOperation.correctionField`). The client used to decide the
    /// gloss language itself.
    func quote(
        imageId: String,
        mode: CreditCaptureMode,
        target: TargetLanguage,
        uiLanguage: UILanguage
    ) async throws
        -> CreditQuote
    /// Idempotent under `key`: a resend answers with the operation it made.
    func accept(_ pending: PendingAccept) async throws -> CreditOperation
    func operation(id: String) async throws -> CreditOperation
    func cancel(id: String) async throws -> CreditOperation
}

@MainActor
struct LiveCreditCaptureAPI: CreditCaptureAPI {
    var api: APIClient = .shared

    func catalog() async throws -> CreditCatalog {
        try await self.api.get(.creditCatalog)
    }

    func wallet() async throws -> CreditWallet {
        try await self.api.get(.creditWallet)
    }

    func operations() async throws -> [CreditOperation] {
        struct List: Decodable { let operations: [CreditOperation] }
        let list: List = try await self.api.get(.aiOperations)
        return list.operations
    }

    func image(id: String) async throws -> AtlasImageSummary {
        struct Detail: Decodable { let image: AtlasImageSummary }
        let detail: Detail = try await self.api.get(.atlasImage(id: id))
        return detail.image
    }

    func upload(photo: Data) async throws -> AtlasImageSummary {
        struct Upload: Decodable { let image: AtlasImageSummary }
        let response: Upload = try await self.api.upload(
            .creditImages,
            fileField: "file",
            filename: "atlas-photo.jpg",
            mimeType: "image/jpeg",
            data: photo
        )
        return response.image
    }

    func quote(
        imageId: String,
        mode: CreditCaptureMode,
        target: TargetLanguage,
        uiLanguage: UILanguage
    ) async throws
        -> CreditQuote
    {
        struct Payload: Encodable {
            let imageId: String
            let feature: String
            let targetLanguage: String
            let uiLanguage: String
        }
        return try await self.api.post(
            .aiQuotes,
            body: Payload(
                imageId: imageId,
                feature: mode.feature,
                targetLanguage: target.rawValue,
                uiLanguage: uiLanguage.rawValue
            )
        )
    }

    func accept(_ pending: PendingAccept) async throws -> CreditOperation {
        struct Payload: Encodable { let quoteId: String }
        return try await self.api.postIdempotent(
            .aiOperations,
            body: Payload(quoteId: pending.quoteId),
            key: pending.key
        )
    }

    func operation(id: String) async throws -> CreditOperation {
        try await self.api.get(.aiOperation(id: id))
    }

    func cancel(id: String) async throws -> CreditOperation {
        try await self.api.post(.aiOperationCancel(id: id), body: Empty())
    }
}

/// Where an unanswered accept waits between launches, one per account and
/// billing environment.
@MainActor
protocol PendingAcceptJournal {
    func load(account: UUID, environment: String) -> PendingAccept?
    func save(_ pending: PendingAccept, account: UUID, environment: String)
    func clear(account: UUID, environment: String)
}

@MainActor
struct DefaultsPendingAcceptJournal: PendingAcceptJournal {
    var defaults: UserDefaults = .standard

    private func key(_ account: UUID, _ environment: String) -> String {
        "tuji.credit-operation.\(account.uuidString.lowercased()).\(environment)"
    }

    func load(account: UUID, environment: String) -> PendingAccept? {
        self.defaults.data(forKey: self.key(account, environment))
            .flatMap { try? JSONDecoder().decode(PendingAccept.self, from: $0) }
    }

    func save(_ pending: PendingAccept, account: UUID, environment: String) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        self.defaults.set(data, forKey: self.key(account, environment))
    }

    func clear(account: UUID, environment: String) {
        self.defaults.removeObject(forKey: self.key(account, environment))
    }
}

/// The photos whose paid result 換一張 walked away from, one list per account. 拍照新增 stops
/// reopening on them; 圖片詳情's 繼續確認 still does. Kept on this phone only: the result is
/// not gone, just no longer in the way.
@MainActor
protocol SetAsideJournal {
    func load(account: UUID) -> Set<String>
    func add(_ imageId: String, account: UUID)
}

@MainActor
struct DefaultsSetAsideJournal: SetAsideJournal {
    var defaults: UserDefaults = .standard

    private func key(_ account: UUID) -> String {
        "tuji.credit-operation.set-aside.\(account.uuidString.lowercased())"
    }

    func load(account: UUID) -> Set<String> {
        Set(self.defaults.stringArray(forKey: self.key(account)) ?? [])
    }

    func add(_ imageId: String, account: UUID) {
        self.defaults.set(self.load(account: account).union([imageId]).sorted(), forKey: self.key(account))
    }
}

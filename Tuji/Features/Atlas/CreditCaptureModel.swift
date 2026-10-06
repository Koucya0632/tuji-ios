import Foundation
import Observation
import os
import UIKit

/// 點數版拍照新增：選模式 → 拍照/裁切（只留在本機）→ 開始識別（上傳、報價、扣點一次做完）→ 選候選建卡。
/// 普通識別完成後，同一張照片可補差價升級成高精度；價格由伺服器決定，報價和畫面上的價格不符就停下來讓使用者確認。
@MainActor
@Observable
final class CreditCaptureModel {
    enum Mode: String { case primary, precision
        var feature: String {
            self == .primary ? "atlas.recognize.primary" : "atlas.recognize.precision"
        }
    }

    struct Pending: Codable, Equatable { let quoteId: String
        let key: String
    }

    var mode: Mode = .primary
    /// The cropped photo, still on the phone. Nothing is uploaded until 開始識別.
    private(set) var photo: Data?
    private(set) var image: AtlasImageSummary?
    private(set) var wallet: CreditWallet?
    private(set) var catalog: CreditCatalog?
    /// Only set when the server's price differs from the one on screen.
    private(set) var quote: CreditQuote?
    private(set) var operation: CreditOperation?
    private(set) var history: [CreditOperation] = []
    private(set) var pending: Pending?
    private(set) var busy = false
    private(set) var message: String?
    private(set) var selectedCandidateId: String?

    // MARK: Correction form (same fields as the free flow)

    var lemma = ""
    var displayZhHant = ""
    /// The ja/en meaning a cross-language capture edits; empty otherwise.
    var displayGloss = ""
    /// What the chosen candidate put in each field, so the form can mark the AI's guess.
    private(set) var suggestion: AtlasCaptureVM.Suggestion?
    private let api: APIClient
    private let queue: AtlasCaptureQueue
    private var owner: UUID?
    private var generation = 0
    /// Consecutive failed polls; one dropped request mid-run is not worth a banner.
    private var pollFailures = 0
    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "credit-capture")
    private static let pollFailureLimit = 3
    private var pollMessage: String {
        tujiLocalized("暫時無法連線，請重試同步。")
    }

    private var journalKey: String? {
        guard let owner, let catalog else { return nil }
        return "tuji.credit-operation.\(owner.uuidString.lowercased()).\(catalog.environment)"
    }

    init(api: APIClient = .shared, queue: AtlasCaptureQueue = .shared) {
        self.api = api
        self.queue = queue
    }

    // MARK: Prices

    var recognitionPrice: Int? {
        self.catalog?.policy?.recognition
    }

    var precisionPrice: Int? {
        self.catalog?.policy?.precision
    }

    var upgradePrice: Int? {
        self.catalog?.policy?.precisionUpgrade
    }

    var price: Int? {
        self.mode == .primary ? self.recognitionPrice : self.precisionPrice
    }

    var operationsEnabled: Bool {
        self.catalog?.operationsEnabled == true && self.wallet?.reconciliationRequired != true
    }

    func affordable(_ points: Int?) -> Bool {
        points.map { (self.wallet?.available ?? 0) >= $0 } ?? false
    }

    // MARK: Results for the photo on screen

    /// Both runs on this photo, so 普通／高精度 can be switched without paying again.
    func run(_ mode: Mode) -> CreditOperation? {
        guard let imageId = self.operation?.imageId else { return nil }
        var runs: [CreditOperation] = self.history
        if let current = self.operation { runs.insert(current, at: 0) }
        return runs.first { $0.imageId == imageId && $0.feature == mode.feature && $0.state != "released" }
    }

    var shownMode: Mode? {
        self.operation.map { $0.feature == Mode.precision.feature ? .precision : .primary }
    }

    var canUpgrade: Bool {
        self.shownMode == .primary && self.operation?.state == "committed" && self.run(.precision) == nil &&
            self.operation?.confirmedItemId == nil
    }

    func show(_ mode: Mode) {
        guard let run = self.run(mode), run.id != self.operation?.id else { return }
        self.operation = run
        self.clearSelection()
    }

    // MARK: Lifecycle

    func load() async {
        guard case let .signedIn(user) = AuthService.shared.state else { return }
        if self.owner != user.id { self.generation += 1
            self.owner = user.id
            self.reset()
            self.wallet = nil
            self.pending = nil
            self.history = []
        }
        let stamp = self.generation
        await self.act {
            let catalog: CreditCatalog = try await self.api.get(.creditCatalog)
            guard self.valid(stamp) else { return }
            self.catalog = catalog
            if let key = self.journalKey, let data = UserDefaults.standard.data(forKey: key) {
                self.pending = try? JSONDecoder().decode(Pending.self, from: data)
            }
            let wallet: CreditWallet = try await self.api.get(.creditWallet)
            guard self.valid(stamp) else { return }
            self.apply(wallet)
            struct List: Decodable { let operations: [CreditOperation] }
            let list: List = try await self.api.get(.aiOperations)
            guard self.valid(stamp) else { return }
            self.history = list.operations
            if self.operation == nil, self.photo == nil {
                self.operation = Self.resumable(in: list.operations, queued: self.queue.creditOperationIds)
                if let imageId = self.operation?.imageId {
                    struct Detail: Decodable { let image: AtlasImageSummary }
                    // The crop never left this phone's last session; show the upload instead.
                    let detail: Detail? = try? await self.api.get(.atlasImage(id: imageId))
                    guard self.valid(stamp), self.operation?.imageId == imageId else { return }
                    self.image = detail?.image
                }
            }
        }
    }

    /// 換一張: back to the source chooser. Results already paid for stay in history.
    func reset() {
        self.photo = nil
        self.image = nil
        self.operation = nil
        self.quote = nil
        self.clearSelection()
        self.message = nil
        self.pollFailures = 0
    }

    func setPhoto(_ data: Data) {
        self.reset()
        self.photo = data
    }

    private func valid(_ stamp: Int) -> Bool {
        guard case let .signedIn(user) = AuthService.shared.state else { return false }
        return stamp == self.generation && self.owner == user.id
    }

    private func apply(_ wallet: CreditWallet) {
        guard case let .signedIn(user) = AuthService.shared.state, self.owner == user.id else { return }
        if self.wallet.map({ wallet.isNewer(than: $0) }) ?? true { self.wallet = wallet }
    }

    private func act(_ run: () async throws -> Void) async {
        guard !self.busy else { return }
        self.busy = true
        self.message = nil
        defer { self.busy = false }
        do { try await run() }
        catch { self.message = error.localizedDescription }
    }

    // MARK: Recognition

    /// 開始識別: upload (once per photo), quote, and accept when the quote matches the price shown.
    func start(language: TargetLanguage, glossLanguage: String?) async {
        guard self.pending == nil, self.operationsEnabled, let photo = self.photo,
              let expected = self.price
        else { return }
        let stamp = self.generation, mode = self.mode
        var quote: CreditQuote?
        await self.act {
            if self.image == nil {
                struct Upload: Decodable { let image: AtlasImageSummary }
                let response: Upload = try await self.api.upload(
                    .creditImages,
                    fileField: "file",
                    filename: "atlas-photo.jpg",
                    mimeType: "image/jpeg",
                    data: photo
                )
                guard self.valid(stamp) else { return }
                self.image = response.image
            }
            guard let imageId = self.image?.id else { return }
            quote = try await self.requestQuote(
                imageId: imageId,
                mode: mode,
                language: language,
                glossLanguage: glossLanguage
            )
        }
        await self.proceed(quote, expected: expected, stamp: stamp)
    }

    /// 普通識別 → 高精度: same photo, pay the difference.
    func upgrade(language: TargetLanguage, glossLanguage: String?) async {
        guard self.pending == nil, self.operationsEnabled, self.canUpgrade, let imageId = self.operation?.imageId,
              let expected = self.upgradePrice
        else { return }
        let stamp = self.generation
        var quote: CreditQuote?
        await self.act {
            // The run keeps the language it was paid for; a later settings change does not apply here.
            let target = TargetLanguage(rawValue: self.operation?.targetLanguage ?? "") ?? language
            quote = try await self.requestQuote(
                imageId: imageId,
                mode: .precision,
                language: target,
                glossLanguage: glossLanguage
            )
        }
        await self.proceed(quote, expected: expected, stamp: stamp)
    }

    private func requestQuote(
        imageId: String,
        mode: Mode,
        language: TargetLanguage,
        glossLanguage: String?
    ) async throws
        -> CreditQuote
    {
        struct Payload: Encodable { let imageId: String
            let feature: String
            let targetLanguage: String
            let glossLanguage: String?
        }
        return try await self.api.post(
            .aiQuotes,
            body: Payload(
                imageId: imageId,
                feature: mode.feature,
                targetLanguage: language.rawValue,
                glossLanguage: glossLanguage
            )
        )
    }

    private func proceed(_ quote: CreditQuote?, expected: Int, stamp: Int) async {
        guard let quote, self.valid(stamp) else { return }
        if quote.points == expected { self.quote = quote
            await self.accept()
        } else { self.quote = quote
            self.message = tujiLocalized("價格已更新，請確認後再開始。")
        }
    }

    func cancelQuote() {
        self.quote = nil
    }

    func accept() async {
        guard let journal = self.journalKey else { return }
        let stamp = self.generation
        await self.act {
            guard let request = self.pending ?? self.quote.map({ Pending(
                quoteId: $0.id,
                key: UUID().uuidString.lowercased()
            ) })
            else { return }
            try UserDefaults.standard.set(JSONEncoder().encode(request), forKey: journal)
            self.pending = request
            struct Payload: Encodable { let quoteId: String }
            do {
                let operation: CreditOperation = try await self.api.postIdempotent(
                    .aiOperations,
                    body: Payload(quoteId: request.quoteId),
                    key: request.key
                )
                guard self.valid(stamp) else { return }
                self.operation = operation
                self.clearSelection()
                self.quote = nil
                self.pending = nil
                self.history = [operation] + self.history.filter { $0.id != operation.id }
                UserDefaults.standard.removeObject(forKey: journal)
                let wallet: CreditWallet = try await self.api.get(.creditWallet)
                guard self.valid(stamp) else { return }
                self.apply(wallet)
            } catch {
                // Keep unknown outcomes; only an explicit rejection permits a new quote.
                if case let APIError.conflict(reason, _) = error,
                   self.valid(stamp), [
                       "quote_expired",
                       "insufficient_credits",
                       "capacity_full",
                       "image_changed",
                       "operation_busy",
                       "idempotency_conflict",
                       "credits_reconciliation_required"
                   ].contains(reason ?? "")
                {
                    self.pending = nil
                    self.quote = nil
                    UserDefaults.standard.removeObject(forKey: journal)
                }
                throw error
            }
        }
    }

    func poll() async {
        guard let id = self.operation?.id, self.operation?.needsPolling == true else { return }
        let stamp = self.generation
        do {
            let value: CreditOperation = try await self.api.get(.aiOperation(id: id))
            guard self.valid(stamp), self.operation?.id == id else { return }
            self.operation = value
            self.history = [value] + self.history.filter { $0.id != id }
            let wallet: CreditWallet = try await self.api.get(.creditWallet)
            guard self.valid(stamp) else { return }
            self.apply(wallet)
            self.pollFailures = 0
            // Only lift the banner poll() raised; other messages belong to their own actions.
            if self.message == self.pollMessage { self.message = nil }
        } catch {
            guard self.valid(stamp) else { return }
            self.pollFailures += 1
            self.log.error("poll failed (\(self.pollFailures)): \(error.localizedDescription, privacy: .public)")
            if self.pollFailures >= Self.pollFailureLimit { self.message = self.pollMessage }
        }
    }

    func cancelOperation() async {
        guard let id = self.operation?.id else { return }
        let stamp = self.generation
        await self.act {
            let value: CreditOperation = try await self.api.post(.aiOperationCancel(id: id), body: Empty())
            guard self.valid(stamp) else { return }
            self.operation = value
            self.history = [value] + self.history.filter { $0.id != id }
            let wallet: CreditWallet = try await self.api.get(.creditWallet)
            guard self.valid(stamp) else { return }
            self.apply(wallet)
        }
    }

    // MARK: Card

    var secondField: CaptureSecondField {
        CaptureCorrectionFields.second(
            ui: UILanguage(code: SettingsStore.shared.uiLang),
            target: TargetLanguage(rawValue: self.operation?.targetLanguage ?? "") ?? SettingsStore.shared
                .learningDirection.targetLanguage
        )
    }

    /// Tapping a chip is an explicit choice, so it replaces whatever the fields hold.
    func select(_ candidate: CreditCandidate) {
        self.selectedCandidateId = candidate.id
        self.lemma = candidate.label
        self.displayZhHant = candidate.zhHant
        self.displayGloss = candidate.gloss ?? ""
        self.suggestion = .init(lemma: self.lemma, zhHant: self.displayZhHant, gloss: self.displayGloss)
    }

    private func clearSelection() {
        self.selectedCandidateId = nil
        self.lemma = ""
        self.displayZhHant = ""
        self.displayGloss = ""
        self.suggestion = nil
    }

    func isStillSuggested(_ field: AtlasCaptureVM.SuggestedField) -> Bool {
        guard let s = self.suggestion else { return false }
        return switch field {
        case .lemma: !s.lemma.isEmpty && s.lemma == self.lemma
        case .zhHant: !s.zhHant.isEmpty && s.zhHant == self.displayZhHant
        case .gloss: !s.gloss.isEmpty && s.gloss == self.displayGloss
        }
    }

    var canConfirm: Bool {
        !self.busy && self.selectedCandidateId != nil && !Self.trim(self.lemma).isEmpty && !Self
            .trim(self.displayZhHant).isEmpty
    }

    var duplicateLemmaWarning: String? {
        let trimmed = Self.trim(self.lemma)
        guard !trimmed.isEmpty else { return nil }
        let exists = AtlasStore.shared.items.contains {
            Self.trim($0.lemma).caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return exists ? tujiLocalized("你已經有一張「\(trimmed)」的卡片，這會再新增一張。") : nil
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 確認並生成卡片. Returns true once the card exists, so the sheet can close.
    /// 確認並生成卡片: hand the confirm → cards → fill-in tail to 生成佇列 and
    /// return, so the sheet closes at once and 我做的 shows the card being made.
    /// Not `async`, like the free flow's `submit()`: the work it commits
    /// outlives the sheet by design.
    func confirm() -> Bool {
        guard self.canConfirm, let operation = self.operation,
              let candidate = operation.result?.candidates.first(where: { $0.id == self.selectedCandidateId })
        else { return false }
        // The gloss field only exists for a cross-language capture; elsewhere the server keeps the candidate's.
        let gloss = self.secondField == .gloss && !Self.trim(self.displayGloss).isEmpty ? Self
            .trim(self.displayGloss) : nil
        self.queue.enqueue(
            credit: CreditConfirmRequest(
                operationId: operation.id,
                candidateId: candidate.id,
                lemma: Self.trim(self.lemma),
                displayZhHant: Self.trim(self.displayZhHant),
                displayGloss: gloss
            ),
            imageId: operation.imageId,
            thumbnail: self.photo.flatMap(UIImage.init(data:))
        )
        self.reset()
        return true
    }

    /// The card was saved but syncing it failed: retry without confirming again.
    func syncCards() async -> Bool {
        guard let itemId = self.operation?.confirmedItemId else { return false }
        var synced = false
        await self.act {
            _ = try await LiveAtlasRepository.shared.createCards(
                itemId: itemId,
                cardTypes: ["image_recall", "flashcard"]
            )
            await AtlasStore.shared.sync(.full)
            await LiveAtlasMutationRefresher().refresh(after: .captureCompleted)
            synced = true
        }
        return synced
    }
}

extension CreditOperation {
    var isRunning: Bool {
        ["reserved", "running", "reconciling"].contains(self.state)
    }
}

extension CreditCaptureModel {
    /// Work already paid for that the screen should reopen on: a run in flight, else a result
    /// nobody has picked from yet. A photo's 普通 and 高精度 runs share one card, so a card made
    /// from either finishes both. One 生成佇列 is already confirming is not waiting either.
    static func resumable(in operations: [CreditOperation], queued: Set<String> = []) -> CreditOperation? {
        let finished = Set(operations.filter { $0.confirmedItemId != nil }.map(\.imageId))
        return operations.first(where: \.isRunning) ?? operations.first {
            $0.state == "committed" && $0.confirmedItemId == nil && !finished.contains($0.imageId) &&
                !queued.contains($0.id)
        }
    }
}

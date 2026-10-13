import Foundation
import Observation
import os
import UIKit

/// 拍照新增：選模式 → 拍照/裁切（只留在本機）→ 開始識別（上傳、報價、扣點一次做完）→ 選候選建卡。
/// 普通識別完成後，同一張照片可補差價升級成高精度；價格由伺服器決定，報價和畫面上的價格不符就停下來讓使用者確認。
///
/// One paid recognition, start to card. The screen renders `panel` and calls
/// the methods below; everything that decides whether points move — and the
/// polling that watches a run — lives here, behind seams a test can stand on
/// (`CreditCaptureSeams.swift`).
@MainActor
@Observable
final class CreditCaptureModel {
    typealias Mode = CreditCaptureMode

    /// What the sheet shows. One answer, derived in one place — the screen used
    /// to work it out with a ladder of `if`s over six properties.
    enum Panel {
        /// Choose 普通／高精度 and a photo.
        case source
        /// A photo is chosen; 開始識別 has not been pressed, or its upload and
        /// quote are under way (`busy`).
        case ready
        case recognizing(CreditOperation)
        /// A relaunch found an accept nobody answered. Resending it is safe.
        case unansweredAccept
        /// The server priced differently from the screen: ask, don't charge.
        case priceChanged(CreditQuote)
        /// The run ended without a result; the points were never taken.
        case released(CreditOperation)
        /// The card exists but its review cards did not sync.
        case cardUnsynced(CreditOperation)
        case result(CreditOperation)
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
    private(set) var pending: PendingAccept?
    private(set) var busy = false
    private(set) var message: String?
    /// 校正表單 for the result on screen.
    var form = CaptureCorrectionForm()

    /// The photo 圖片詳情's 繼續確認 asked for: the sheet opens on that photo's result, not
    /// on whichever unpicked result is newest.
    private let resume: String?
    private let api: any CreditCaptureAPI
    private let queue: AtlasCaptureQueue
    /// Who is signed in, asked live: an answer that arrives after a sign-out or
    /// an account switch must not land on the next account's screen.
    private let account: @MainActor () -> UUID?
    private let pendingJournal: any PendingAcceptJournal
    private let setAside: any SetAsideJournal
    private let language: any LanguageContext
    /// The lemmas this account already has cards for.
    private let ownedLemmas: @MainActor () -> [String]
    private let cards: any AtlasCardGenerating
    private let mutations: any AtlasMutationRefreshing
    private let sleep: (Duration) async throws -> Void

    private var owner: UUID?
    private var generation = 0
    /// Consecutive failed polls; one dropped request mid-run is not worth a banner.
    private var pollFailures = 0
    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "credit-capture")
    private static let pollFailureLimit = 3
    private var pollMessage: String {
        tujiLocalized("暫時無法連線，請重試同步。")
    }

    /// The only answers to an accept that mean "this accept is dead": anything
    /// else leaves the outcome unknown, and an unknown accept is kept so the
    /// same key can be resent.
    static let acceptRejections: Set<String> = [
        "quote_expired", "insufficient_credits", "capacity_full", "image_changed",
        "operation_busy", "idempotency_conflict", "credits_reconciliation_required"
    ]

    init(
        resume: String? = nil,
        api: any CreditCaptureAPI = LiveCreditCaptureAPI(),
        queue: AtlasCaptureQueue = .shared,
        account: @escaping @MainActor () -> UUID? = {
            if case let .signedIn(user) = AuthService.shared.state { return user.id }
            return nil
        },
        pendingJournal: any PendingAcceptJournal = DefaultsPendingAcceptJournal(),
        setAside: any SetAsideJournal = DefaultsSetAsideJournal(),
        language: any LanguageContext = SettingsStore.shared,
        ownedLemmas: @escaping @MainActor () -> [String] = { AtlasStore.shared.items.map(\.lemma) },
        cards: any AtlasCardGenerating = AtlasStore.shared,
        mutations: any AtlasMutationRefreshing = LiveAtlasMutationRefresher(),
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.resume = resume
        self.api = api
        self.queue = queue
        self.account = account
        self.pendingJournal = pendingJournal
        self.setAside = setAside
        self.language = language
        self.ownedLemmas = ownedLemmas
        self.cards = cards
        self.mutations = mutations
        self.sleep = sleep
    }

    // MARK: What the sheet shows

    var panel: Panel {
        if self.recognitionInFlight {
            // The accept journals `pending` before it sends, and the recovery
            // panels below are for after a failure; mid-request they read as one.
            return self.operation.map(Panel.recognizing) ?? .ready
        }
        if self.pending != nil { return .unansweredAccept }
        if let quote = self.quote { return .priceChanged(quote) }
        guard let operation = self.operation else { return self.photo == nil ? .source : .ready }
        if operation.isRunning { return .recognizing(operation) }
        if operation.status == .released { return .released(operation) }
        if operation.confirmedItemId != nil { return .cardUnsynced(operation) }
        return .result(operation)
    }

    /// Upload → quote → accept under way, for a new photo or a 高精度 upgrade of
    /// the result on screen. Not a relaunch's leftover `pending` with nothing to
    /// show, which still needs its 重試同步.
    private var recognitionInFlight: Bool {
        guard self.busy else { return false }
        if self.operation == nil { return self.photo != nil }
        return self.pending != nil || self.quote != nil
    }

    /// Which of the five steps the indicator marks.
    var step: Int {
        if self.operation?.status == .committed { return 3 }
        if self.operation?.isRunning == true { return 2 }
        if self.photo != nil { return 1 }
        return 0
    }

    /// Changes whenever there is a different run to watch, or the same run
    /// moved — what the screen keys `watch()` on.
    var watchKey: String {
        "\(self.operation?.id ?? ""):\(self.operation?.state ?? "")"
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
        return runs.first { $0.imageId == imageId && $0.feature == mode.feature && $0.status != .released }
    }

    var shownMode: Mode? {
        self.operation.map { Mode(feature: $0.feature) }
    }

    var canUpgrade: Bool {
        self.shownMode == .primary && self.operation?.status == .committed && self.run(.precision) == nil &&
            self.operation?.confirmedItemId == nil
    }

    func show(_ mode: Mode) {
        guard let run = self.run(mode), run.id != self.operation?.id else { return }
        self.operation = run
        self.form = CaptureCorrectionForm()
    }

    // MARK: Lifecycle

    func load() async {
        guard let user = self.account() else { return }
        if self.owner != user {
            self.generation += 1
            self.owner = user
            self.reset()
            self.wallet = nil
            self.pending = nil
            self.history = []
        }
        let stamp = self.generation
        await self.act {
            let catalog = try await self.api.catalog()
            guard self.valid(stamp) else { return }
            self.catalog = catalog
            self.pending = self.pendingJournal.load(account: user, environment: catalog.environment)
            try await self.refreshWallet(stamp)
            let operations = try await self.api.operations()
            guard self.valid(stamp) else { return }
            self.history = operations
            if self.operation == nil, self.photo == nil {
                try await self.reopen(from: operations, stamp: stamp)
            }
        }
    }

    /// Opens on work already paid for, with its photo — the crop never left this phone's last
    /// session, so the upload is shown instead.
    ///
    /// A result whose photo has been deleted is passed over. Deleting a photo does not close
    /// its run, so the newest unpicked result could be one that can never become a card; the
    /// sheet opened on its candidates with an empty frame, and did so again on every launch.
    private func reopen(from operations: [CreditOperation], stamp: Int) async throws {
        let queued = self.queue.creditOperationIds
        var waiting = operations
        if self.resume == nil, let owner = self.owner {
            // 換一張 said "not this one": only 繼續確認, which names the photo, brings it back.
            let aside = self.setAside.load(account: owner)
            waiting.removeAll { aside.contains($0.imageId) }
        }
        while true {
            let found = if let resume = self.resume {
                CreditOperation.resumable(for: resume, in: waiting, queued: queued)
            } else {
                CreditOperation.resumable(in: waiting, queued: queued)
            }
            guard let found else { return }
            var image: AtlasImageSummary?
            do {
                image = try await self.api.image(id: found.imageId)
            } catch APIError.notFound {
                waiting.removeAll { $0.imageId == found.imageId }
                continue
            } catch {
                // Unreachable is not gone: the result is still worth showing without its photo.
            }
            // A photo chosen while this was in the air wins.
            guard self.valid(stamp), self.operation == nil, self.photo == nil else { return }
            self.operation = found
            self.image = image
            return
        }
    }

    /// 換一張: back to the source chooser, and the result left behind stops reopening here.
    /// It used to come back on every visit, since nothing but a card or deleting the photo
    /// closes a paid result — so 換一張 could never get past it.
    func retake() {
        if let operation = self.operation, operation.status != .released, let owner = self.owner {
            self.setAside.add(operation.imageId, account: owner)
        }
        self.reset()
    }

    /// Back to the source chooser. Results already paid for stay in history.
    private func reset() {
        self.photo = nil
        self.image = nil
        self.operation = nil
        self.quote = nil
        self.form = CaptureCorrectionForm()
        self.message = nil
        self.pollFailures = 0
    }

    func setPhoto(_ data: Data) {
        self.reset()
        self.photo = data
    }

    /// Still the account and the session this request was made for.
    private func valid(_ stamp: Int) -> Bool {
        stamp == self.generation && self.owner != nil && self.owner == self.account()
    }

    private func refreshWallet(_ stamp: Int) async throws {
        let wallet = try await self.api.wallet()
        guard self.valid(stamp) else { return }
        // A slow answer must not walk the balance backwards.
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

    private func adopt(_ operation: CreditOperation) {
        self.operation = operation
        self.history = [operation] + self.history.filter { $0.id != operation.id }
    }

    // MARK: Recognition

    /// 開始識別: upload (once per photo), quote, and accept when the quote matches the price shown.
    func start(language: TargetLanguage) async {
        guard self.pending == nil, self.operationsEnabled, let photo = self.photo,
              let expected = self.price
        else { return }
        let stamp = self.generation, mode = self.mode
        var quote: CreditQuote?
        await self.act {
            if self.image == nil {
                let image = try await self.api.upload(photo: photo)
                guard self.valid(stamp) else { return }
                self.image = image
            }
            guard let imageId = self.image?.id else { return }
            quote = try await self.requestQuote(imageId: imageId, mode: mode, target: language)
        }
        await self.proceed(quote, expected: expected, stamp: stamp)
    }

    /// 普通識別 → 高精度: same photo, pay the difference.
    func upgrade(language: TargetLanguage) async {
        guard self.pending == nil, self.operationsEnabled, self.canUpgrade, let operation = self.operation,
              let expected = self.upgradePrice
        else { return }
        let stamp = self.generation
        var quote: CreditQuote?
        await self.act {
            // The run keeps the language it was paid for; a later settings change does not apply here.
            let target = TargetLanguage(rawValue: operation.targetLanguage) ?? language
            quote = try await self.requestQuote(imageId: operation.imageId, mode: .precision, target: target)
        }
        await self.proceed(quote, expected: expected, stamp: stamp)
    }

    private func requestQuote(imageId: String, mode: Mode, target: TargetLanguage) async throws -> CreditQuote {
        try await self.api.quote(
            imageId: imageId,
            mode: mode,
            target: target,
            uiLanguage: UILanguage(code: self.language.uiLang)
        )
    }

    private func proceed(_ quote: CreditQuote?, expected: Int, stamp: Int) async {
        guard let quote, self.valid(stamp) else { return }
        self.quote = quote
        if quote.points == expected {
            await self.accept()
        } else {
            self.message = tujiLocalized("價格已更新，請確認後再開始。")
        }
    }

    func cancelQuote() {
        self.quote = nil
    }

    /// Accept the quote on screen — or resend the accept a previous attempt left
    /// unanswered, under the key it was first sent with.
    func accept() async {
        guard let user = self.owner, let environment = self.catalog?.environment else { return }
        let stamp = self.generation
        await self.act {
            guard let request = self.pending ?? self.quote.map({
                PendingAccept(quoteId: $0.id, key: UUID().uuidString.lowercased())
            })
            else { return }
            // Journalled before it is sent: an app kill here must find the key.
            self.pendingJournal.save(request, account: user, environment: environment)
            self.pending = request
            do {
                let operation = try await self.api.accept(request)
                guard self.valid(stamp) else { return }
                self.adopt(operation)
                self.form = CaptureCorrectionForm()
                self.quote = nil
                self.pending = nil
                self.pendingJournal.clear(account: user, environment: environment)
                try await self.refreshWallet(stamp)
            } catch {
                // Keep unknown outcomes; only an explicit rejection permits a new quote.
                if case let APIError.conflict(reason, _) = error, self.valid(stamp),
                   Self.acceptRejections.contains(reason ?? "")
                {
                    self.pending = nil
                    self.quote = nil
                    self.pendingJournal.clear(account: user, environment: environment)
                }
                throw error
            }
        }
    }

    /// Follow the run on screen until it ends. The screen starts this whenever
    /// `watchKey` changes and cancels it when it leaves.
    ///
    /// The server starts the run on accept and a 普通 run finishes in about two
    /// seconds, so the first look is early.
    func watch() async {
        var delay: Duration = .seconds(1)
        while self.operation?.isRunning == true, !Task.isCancelled {
            do { try await self.sleep(delay) } catch { return }
            await self.poll()
            delay = .seconds(2)
        }
    }

    func poll() async {
        guard let id = self.operation?.id, self.operation?.isRunning == true else { return }
        let stamp = self.generation
        do {
            let value = try await self.api.operation(id: id)
            guard self.valid(stamp), self.operation?.id == id else { return }
            self.adopt(value)
            try await self.refreshWallet(stamp)
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

    /// Only a run that has not started can be withdrawn.
    var canCancelOperation: Bool {
        self.operation?.status == .reserved
    }

    func cancelOperation() async {
        guard let id = self.operation?.id else { return }
        let stamp = self.generation
        await self.act {
            let value = try await self.api.cancel(id: id)
            guard self.valid(stamp) else { return }
            self.adopt(value)
            try await self.refreshWallet(stamp)
        }
    }

    // MARK: Card

    /// The form this run asked its user for. The server says so when it knows
    /// the interface language the run was quoted under; otherwise the grid
    /// answers, over the language the run was paid for.
    var secondField: CaptureSecondField {
        if let declared = self.operation?.correctionField.flatMap(CaptureSecondField.init(rawValue:)) {
            return declared
        }
        return CaptureCorrectionFields.second(
            ui: UILanguage(code: self.language.uiLang),
            target: TargetLanguage(rawValue: self.operation?.targetLanguage ?? "")
                ?? self.language.learningDirection.targetLanguage
        )
    }

    func candidateMeaning(_ candidate: CreditCandidate) -> String? {
        CaptureCorrectionFields.candidateMeaning(
            second: self.secondField,
            zhHant: candidate.zhHant,
            gloss: candidate.gloss
        )
    }

    var canConfirm: Bool {
        !self.busy && self.form.isComplete
    }

    var duplicateLemmaWarning: String? {
        self.form.duplicate(among: self.ownedLemmas()).map {
            tujiLocalized("你已經有一張「\($0)」的卡片，這會再新增一張。")
        }
    }

    /// 確認並生成卡片: hand the confirm → cards → fill-in tail to 生成佇列 and
    /// return, so the sheet closes at once and 我做的 shows the card being made.
    /// Not `async`: the work it commits outlives the sheet by design.
    func confirm() -> Bool {
        guard self.canConfirm, let operation = self.operation,
              let request = self.form.request(operationId: operation.id, second: self.secondField),
              operation.result?.candidates.contains(where: { $0.id == request.candidateId }) == true
        else { return false }
        self.queue.enqueue(
            credit: request,
            imageId: operation.imageId,
            thumbnail: self.photo.flatMap(UIImage.init(data:))
        )
        self.reset()
        return true
    }

    /// The card was saved but syncing it failed: retry without confirming again.
    /// The same tail 生成佇列 runs, through the same seam.
    func syncCards() async -> Bool {
        guard let itemId = self.operation?.confirmedItemId else { return false }
        var synced = false
        await self.act {
            try await self.cards.generateCards(forItem: itemId)
            await self.cards.reconcile()
            await self.mutations.refresh(after: .captureCompleted)
            synced = true
        }
        return synced
    }
}

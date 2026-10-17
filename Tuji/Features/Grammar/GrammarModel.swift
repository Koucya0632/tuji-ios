import Foundation
import Observation

/// One exchange on the AI 語法 screen: what was asked, and Moira's card once it is
/// back. The conversation is the screen's memory only; 語法紀錄 is what is kept.
struct GrammarTurn: Identifiable, Equatable {
    let input: GrammarInput
    var record: GrammarRecord?
    /// The server refused the request outright; nothing was charged.
    var rejection: String?

    var id: String {
        self.input.requestId
    }

    var failureNote: String? {
        if let rejection { return rejection }
        guard let record, record.status == .failed else { return nil }
        if let message = record.result?.message, !message.isEmpty { return message }
        return record.error == "insufficient_credits" ? tujiLocalized("罐頭點數不足，這次沒有扣點。") :
            tujiLocalized("未能生成有效內容，這次沒有扣點。")
    }
}

@MainActor
@Observable
final class GrammarModel {
    static let queryLimit = 800
    static let contextLimit = 800
    static let compareLimit = 120

    /// The draft in the composer. Sending clears it; the turn keeps what was sent.
    var query: String
    var context = ""
    var compareWith = ""
    /// A grammar point chosen from a clarification.
    var focus = ""
    var difficulty: GrammarDifficulty = .basic
    var practiceType: GrammarPracticeType = .mixed
    var mode: GrammarMode = .explain
    /// The card a next step was drafted from. Cleared when the draft is rewritten.
    private(set) var sourceRecordId: String?
    private(set) var offer: GrammarOffer?
    /// The offer was read from the server since launch, so its balance can
    /// decide spending. One kept from an earlier launch is only shown.
    private(set) var offerCurrent = false
    /// The server said the points are short. The page does not show or judge
    /// the balance itself: the kept one can be behind.
    private(set) var outOfPoints = false
    private(set) var turns: [GrammarTurn] = []
    private(set) var spotlight: Spotlight?
    /// `history` came from a read (or a kept one), not just the empty start:
    /// only then may it stand as a filter's kept list.
    @ObservationIgnored private var historyLoaded = false
    private(set) var history: [GrammarRecord] = []
    private(set) var nextCursor: String?
    private(set) var pending: GrammarInput?
    private(set) var busy = false
    private(set) var loadingHistory = false
    private(set) var message: String?
    private(set) var historyMessage: String?
    /// A next step, a candidate or 改一下 put something into the draft: the view
    /// opens the fields that hold it and moves focus to the composer.
    private(set) var draftTick = 0
    let progress: GrammarProgressStoring
    private let repository: GrammarStudying
    private let offerCache: AssistantOfferCache<GrammarOffer>
    private let historyCache: AssistantHistoryCache<GrammarRecord>
    private let language: LanguageContext
    private let identity: ViewerIdentity
    private let journal: GrammarJournaling
    private let pollInterval: Duration
    private(set) var owner: String?
    private var scope = ""
    private var historyFilter = HistoryFilter()
    private var historyRequest = UUID()

    struct Spotlight: Equatable {
        let id: String
        let tick: Int
    }

    struct HistoryFilter: Equatable {
        var favorite = false
        var mode: GrammarMode?
    }

    /// Another card for the newest turn: for a practice set, 換一組題目 is the main
    /// action; for an explanation or a comparison a second card is mostly the same
    /// card again, so it is a quieter choice under the card.
    enum Regeneration: Equatable {
        case main(maxPoints: Int)
        case secondary(maxPoints: Int)
    }

    init(
        query: String = "",
        repository: GrammarStudying = LiveGrammarRepository(),
        offerCache: AssistantOfferCache<GrammarOffer> = AssistantOfferCaches.grammar,
        historyCache: AssistantHistoryCache<GrammarRecord> = AssistantHistoryCaches.grammar,
        language: LanguageContext = SettingsStore.shared,
        identity: ViewerIdentity = AuthService.shared,
        journal: GrammarJournaling = DefaultsGrammarJournal(),
        progress: GrammarProgressStoring = DefaultsGrammarProgress(),
        pollInterval: Duration = .seconds(2)
    ) {
        self.query = query
        self.repository = repository
        self.offerCache = offerCache
        self.historyCache = historyCache
        self.language = language
        self.identity = identity
        self.journal = journal
        self.progress = progress
        self.pollInterval = pollInterval
    }

    var uiLanguage: String {
        UILanguage(code: self.language.uiLang).rawValue
    }

    var learning: String {
        self.language.learningDirection.rawValue
    }

    /// 語法紀錄 is per account and learning direction; the interface language
    /// changes how new cards are explained, not which saved ones are yours.
    var scopeID: String {
        "\(self.identity.uid ?? "")|\(self.learning)"
    }

    /// Changes when the kept balance stops being trusted; the page loads again on it.
    var offerRevision: Int {
        self.offerCache.revision
    }

    var price: GrammarOffer.Price? {
        self.price(for: self.mode)
    }

    func price(for mode: GrammarMode) -> GrammarOffer.Price? {
        self.offer?.modes.first { $0.mode == mode }
    }

    enum Blocker: Equatable {
        case membership, disabled, insufficientPoints
    }

    var blocker: Blocker? {
        guard let offer = self.offer else { return nil }
        switch offer.reason {
        case .disabled: return .disabled
        case .membership: return .membership
        case nil where !offer.enabled: return .disabled
        case nil: break
        }
        return self.outOfPoints ? .insufficientPoints : nil
    }

    /// Input problems are said beside the field, not by a disabled button alone.
    var tooLong: Bool {
        self.query.count > Self.queryLimit || self.context.count > Self.contextLimit ||
            self.compareWith.count > Self.compareLimit
    }

    var canGenerate: Bool {
        let text = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.canSpend(on: self.mode) && !text.isEmpty && !self.tooLong &&
            text.contains(where: { $0.isLetter || $0.isNumber })
    }

    private func canSpend(on mode: GrammarMode) -> Bool {
        !self.busy && self.pending == nil && self.identity.uid != nil && self.offerCurrent &&
            self.offer?.enabled == true && self.price(for: mode) != nil
    }

    /// Only the newest completed card offers another, and only when it can be paid for.
    func regeneration(for turn: GrammarTurn) -> Regeneration? {
        guard turn.id == self.turns.last?.id, turn.record?.status == .completed,
              self.canSpend(on: turn.input.mode), let price = self.price(for: turn.input.mode)
        else { return nil }
        return turn.input.mode == .practice ? .main(maxPoints: price.maxPoints) :
            .secondary(maxPoints: price.maxPoints)
    }

    func load() async {
        let scope = self.scopeID
        if self.scope != scope {
            // Another account or direction: the draft belonged to the old one. The
            // first load keeps whatever the screen was opened with.
            if !self.scope.isEmpty { self.clearDraft() }
            self.scope = scope
            self.owner = self.identity.uid
            self.turns = []
            self.spotlight = nil
            self.history = []
            self.historyLoaded = false
            self.nextCursor = nil
            self.pending = nil
            self.offer = nil
            self.offerCurrent = false
            self.busy = false
            self.message = nil
        }
        guard let owner = self.owner else { self.message = tujiLocalized("登入後即可使用 AI 語法。")
            return
        }
        // Entering does not read the balance again when this launch already has it.
        if let entry = self.offerCache.entry(owner: owner) {
            self.offer = entry.offer
            self.offerCurrent = entry.current
        }
        if !self.offerCurrent {
            // A first read, or one after a purchase: a shortfall said before is over.
            self.outOfPoints = false
            await self.refreshOffer(scope: scope)
        }
        guard scope == self.scopeID else { return }
        if let input = self.journal.pending(owner: owner)
            .first(where: { $0.learningDirection == self.learning })
        {
            if !self.turns.contains(where: { $0.id == input.requestId }) {
                self.append(GrammarTurn(input: input))
            }
            self.pending = input
            await self.reconcile()
        }
    }

    /// Shared with 助手's prefetch; also how the balance comes back after a card
    /// or a refusal, since neither carries it.
    private func refreshOffer(scope: String) async {
        guard let owner = self.owner else { return }
        let repository = self.repository
        do {
            let offer = try await self.offerCache.load(owner: owner) { try await repository.offer() }
            guard scope == self.scopeID else { return }
            self.offer = offer
            self.offerCurrent = true
        } catch {
            guard scope == self.scopeID else { return }
            self.message = tujiLocalized("暫時無法取得價格，請重新整理。")
        }
    }

    /// The only fresh paid request from the composer. Entry, mode selection, a
    /// candidate and a next step only fill the draft.
    func generate() async {
        guard self.canGenerate else { return }
        let draft = self.draftInput()
        self.clearDraft()
        await self.start(draft)
    }

    /// Another card for what the newest turn asked; a new request, charged again.
    func regenerate(_ turn: GrammarTurn) async {
        guard self.regeneration(for: turn) != nil else { return }
        await self.start(Draft(input: turn.input))
    }

    private struct Draft {
        var mode: GrammarMode
        var query: String
        var context: String
        var compareWith: String
        var focus: String
        var difficulty: GrammarDifficulty
        var practiceType: GrammarPracticeType
        var sourceRecordId: String?

        init(
            mode: GrammarMode,
            query: String,
            context: String,
            compareWith: String,
            focus: String,
            difficulty: GrammarDifficulty,
            practiceType: GrammarPracticeType,
            sourceRecordId: String?
        ) {
            self.mode = mode
            self.query = query
            self.context = context
            self.compareWith = compareWith
            self.focus = focus
            self.difficulty = difficulty
            self.practiceType = practiceType
            self.sourceRecordId = sourceRecordId
        }

        init(input: GrammarInput) {
            self.init(
                mode: input.mode,
                query: input.query,
                context: input.context,
                compareWith: input.compareWith,
                focus: input.focus,
                difficulty: input.difficulty,
                practiceType: input.practiceType,
                sourceRecordId: input.sourceRecordId
            )
        }
    }

    /// Only what the mode reads goes out: a 比較對象 typed for 近似語法 does not
    /// ride along on a 語法解釋 the person switched to.
    private func draftInput() -> Draft {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let compares = self.mode != .explain
        return Draft(
            mode: self.mode,
            query: trim(self.query),
            context: trim(self.context),
            compareWith: compares ? trim(self.compareWith) : "",
            focus: self.focus,
            difficulty: self.mode == .practice ? self.difficulty : .basic,
            practiceType: self.mode == .practice ? self.practiceType : .mixed,
            sourceRecordId: self.sourceRecordId
        )
    }

    private func clearDraft() {
        self.query = ""
        self.context = ""
        self.compareWith = ""
        self.focus = ""
        self.sourceRecordId = nil
    }

    private func start(_ draft: Draft) async {
        guard let price = self.price(for: draft.mode), let offer = self.offer, let owner = self.owner else { return }
        self.outOfPoints = false
        let input = GrammarInput(
            requestId: UUID().uuidString.lowercased(),
            mode: draft.mode,
            query: draft.query,
            context: draft.context,
            compareWith: draft.compareWith,
            focus: draft.focus,
            difficulty: draft.difficulty,
            practiceType: draft.practiceType,
            sourceRecordId: draft.sourceRecordId,
            uiLanguage: self.uiLanguage,
            learningDirection: self.learning,
            pricingVersion: offer.pricingVersion,
            maxPoints: price.maxPoints
        )
        self.journal.save(input, owner: owner)
        self.pending = input
        self.append(GrammarTurn(input: input))
        await self.send(input, owner: owner, scope: self.scopeID)
    }

    private func send(_ input: GrammarInput, owner: String, scope: String) async {
        self.busy = true
        self.message = nil
        defer { if scope == self.scopeID { self.busy = false } }
        do {
            let record = try await self.repository.generate(input)
            guard scope == self.scopeID else { return }
            self.accept(record, owner: owner)
            if record.status == .pending { await self.poll(input, owner: owner, scope: scope) }
            await self.refreshOffer(scope: scope)
        } catch {
            guard scope == self.scopeID else { return }
            if Self.definitelyRejected(error) {
                self.journal.remove(id: input.requestId, owner: owner)
                self.pending = nil
                self.update(input.requestId) { $0.rejection = Self.failureMessage(error) }
                if case let APIError.conflict(reason, _) = error, reason == "insufficient_credits" {
                    self.outOfPoints = true
                }
                await self.refreshOffer(scope: scope)
            } else {
                // The answer may only be late: ask after the same request rather than starting another.
                await self.poll(input, owner: owner, scope: scope)
            }
        }
    }

    func reconcile() async {
        guard !self.busy, let input = self.pending, let owner = self.owner else { return }
        let scope = self.scopeID
        self.busy = true
        defer { if scope == self.scopeID { self.busy = false } }
        do {
            let record = try await self.repository.record(id: input.requestId)
            guard scope == self.scopeID else { return }
            self.accept(record, owner: owner)
            if record.status == .pending { await self.poll(input, owner: owner, scope: scope) }
            await self.refreshOffer(scope: scope)
        } catch APIError.notFound {
            guard scope == self.scopeID else { return }
            // The original POST may never have arrived; this is still the user's authorized request.
            self.busy = false
            await self.send(input, owner: owner, scope: scope)
        } catch {
            guard scope == self.scopeID else { return }
            self.message = tujiLocalized("確認生成結果中，請稍後重試確認。")
        }
    }

    private func poll(_ input: GrammarInput, owner: String, scope: String) async {
        for _ in 0..<80 {
            do {
                try await Task.sleep(for: self.pollInterval)
                guard scope == self.scopeID else { return }
                let record = try await self.repository.record(id: input.requestId)
                guard scope == self.scopeID else { return }
                self.accept(record, owner: owner)
                if record.status != .pending { return }
            } catch { break }
        }
        if scope == self.scopeID, self.pending != nil {
            self.message = tujiLocalized("確認生成結果中，請稍後重試確認。")
        }
    }

    private func accept(_ record: GrammarRecord, owner: String) {
        guard record.status != .pending else { return }
        if record.status == .failed, record.error == "insufficient_credits" { self.outOfPoints = true }
        self.historyCache.invalidate(owner: owner)
        self.journal.remove(id: record.id, owner: owner)
        if self.pending?.requestId == record.id { self.pending = nil }
        if record.status == .deleted {
            self.turns.removeAll { $0.id == record.id }
        } else if self.turns.contains(where: { $0.id == record.id }) {
            // The card is far taller than the wait it replaces: bring its turn up again.
            self.update(record.id) { $0.record = record }
            self.focus(record.id)
        }
        self.message = nil
    }

    // MARK: - Drafts

    /// A clarification's grammar point goes into the draft; spending stays with 送出.
    func choose(_ candidate: GrammarCandidate, for turn: GrammarTurn) {
        self.fill(Draft(input: turn.input))
        self.focus = candidate.focus
        self.mode = turn.input.mode
    }

    /// Typing over the draft makes it the person's own question, no longer the
    /// next step of an earlier card.
    func editQuery() {
        self.focus = ""
        self.sourceRecordId = nil
        self.message = nil
    }

    /// 改一下: what a turn asked goes back into the composer.
    func edit(_ turn: GrammarTurn) {
        self.fill(Draft(input: turn.input))
        self.mode = turn.input.mode
    }

    /// 比較近似語法 / 練習這個語法 under an explanation.
    func next(_ mode: GrammarMode, from record: GrammarRecord) {
        guard let input = record.input, case let .explain(value)? = record.result?.content else { return }
        self.fill(Draft(
            mode: mode,
            query: value.summary.name,
            context: input.context,
            compareWith: "",
            focus: "",
            difficulty: self.difficulty,
            practiceType: self.practiceType,
            sourceRecordId: record.id
        ))
        self.mode = mode
    }

    /// 解釋 A / 解釋 B / 練習分辨 under a comparison.
    enum ComparisonStep { case explainA, explainB, practice }
    func follow(_ step: ComparisonStep, from record: GrammarRecord) {
        guard let input = record.input, case let .compare(value)? = record.result?.content else { return }
        let mode: GrammarMode = step == .practice ? .practice : .explain
        self.fill(Draft(
            mode: mode,
            query: step == .explainB ? value.b.name : value.a.name,
            context: input.context,
            compareWith: step == .practice ? value.b.name : "",
            focus: "",
            difficulty: self.difficulty,
            practiceType: self.practiceType,
            sourceRecordId: record.id
        ))
        self.mode = mode
    }

    private func fill(_ draft: Draft) {
        self.query = draft.query
        self.context = draft.context
        self.compareWith = draft.compareWith
        self.focus = draft.focus
        self.difficulty = draft.difficulty
        self.practiceType = draft.practiceType
        self.sourceRecordId = draft.sourceRecordId
        self.message = nil
        self.draftTick += 1
    }

    /// A card from 語法紀錄 joins the conversation once, in whatever language it
    /// was explained in, and is brought into view.
    func open(_ record: GrammarRecord) {
        guard let input = record.input else { return }
        if self.turns.contains(where: { $0.id == record.id }) {
            self.update(record.id) { $0.record = record }
            self.focus(record.id)
        } else {
            self.append(GrammarTurn(input: input, record: record))
        }
        self.message = nil
    }

    // MARK: - 語法紀錄

    /// Opening 語法紀錄 again shows the list this launch already read; `force`
    /// (pull to refresh, 重試) reads it anyway.
    func loadHistory(_ filter: HistoryFilter, more: Bool = false, force: Bool = false) async {
        guard !more || !self.loadingHistory else { return }
        if !more, !force, let owner = self.owner,
           let kept = self.historyCache.page(owner: owner, filter: self.historyFilterKey(filter))
        {
            self.historyRequest = UUID()
            self.loadingHistory = false
            self.historyMessage = nil
            self.historyFilter = filter
            self.history = kept.records
            self.historyLoaded = true
            self.nextCursor = kept.nextCursor
            return
        }
        let request = UUID()
        self.historyRequest = request
        self.loadingHistory = true
        self.historyMessage = nil
        let scope = self.scopeID
        defer { if request == self.historyRequest { self.loadingHistory = false } }
        do {
            let list = try await self.repository.records(
                learning: self.learning,
                favorite: filter.favorite,
                mode: filter.mode,
                cursor: more ? self.nextCursor : nil
            )
            guard scope == self.scopeID, request == self.historyRequest else { return }
            self.historyFilter = filter
            self.history = more ? self.history + list.records : list.records
            self.historyLoaded = true
            self.nextCursor = list.nextCursor
            self.keepHistory()
        } catch {
            if scope == self.scopeID, request == self.historyRequest {
                self.historyMessage = tujiLocalized("無法讀取語法紀錄，請重試。")
            }
        }
    }

    func toggleFavorite(_ record: GrammarRecord) async {
        let scope = self.scopeID
        do {
            let updated = try await self.repository.favorite(id: record.id, value: !record.favorite)
            guard scope == self.scopeID else { return }
            self.update(updated.id) { $0.record = updated }
            self.history = self.history.compactMap { row in
                guard row.id == updated.id else { return row }
                return self.historyFilter.favorite && !updated.favorite ? nil : updated
            }
            // The other filters' lists hold this row too: only the open one is right.
            if let owner = self.owner { self.historyCache.invalidate(owner: owner) }
            self.keepHistory()
        } catch {
            guard scope == self.scopeID else { return }
            self.message = tujiLocalized("無法更新書籤，請重試。")
            self.historyMessage = self.message
        }
    }

    /// Deleting a set also forgets how far this device got through it.
    func delete(_ record: GrammarRecord) async {
        let scope = self.scopeID
        do {
            try await self.repository.delete(id: record.id)
            guard scope == self.scopeID else { return }
            if let owner = self.owner {
                self.progress.remove(owner: owner, learning: self.learning, setId: record.id)
            }
            self.history.removeAll { $0.id == record.id }
            self.turns.removeAll { $0.id == record.id }
            if let owner = self.owner { self.historyCache.invalidate(owner: owner) }
            self.keepHistory()
        } catch { self.historyMessage = tujiLocalized("無法刪除紀錄，請重試。") }
    }

    private func historyFilterKey(_ filter: HistoryFilter) -> String {
        "\(self.learning)|\(filter.favorite)|\(filter.mode?.rawValue ?? "")"
    }

    /// The list on screen, as the kept one for its filter.
    private func keepHistory() {
        guard self.historyLoaded, let owner = self.owner else { return }
        self.historyCache.store(
            .init(records: self.history, nextCursor: self.nextCursor),
            owner: owner,
            filter: self.historyFilterKey(self.historyFilter)
        )
    }

    private func append(_ turn: GrammarTurn) {
        self.turns.append(turn)
        self.focus(turn.id)
    }

    private func focus(_ id: String) {
        self.spotlight = Spotlight(id: id, tick: (self.spotlight?.tick ?? 0) + 1)
    }

    private func update(_ id: String, _ change: (inout GrammarTurn) -> Void) {
        guard let index = self.turns.firstIndex(where: { $0.id == id }) else { return }
        change(&self.turns[index])
    }

    private static func definitelyRejected(_ error: Error) -> Bool {
        switch error {
        case APIError.unauthorized, APIError.forbidden, APIError.rateLimited, APIError.conflict: true
        case let APIError.server(status, _): status == 400 || status == 413
        default: false
        }
    }

    private static func failureMessage(_ error: Error) -> String {
        switch error {
        case let APIError.conflict(reason, _) where reason == "price_changed": tujiLocalized("價格已更新，請確認新價格後再生成。")
        case let APIError.conflict(reason, _) where reason == "insufficient_credits": tujiLocalized("罐頭點數不足，這次沒有扣點。")
        case APIError.rateLimited: tujiLocalized("請求太頻繁，請稍後再試")
        case APIError.unauthorized: tujiLocalized("登入後即可使用 AI 語法。")
        default: tujiLocalized("目前無法生成，請檢查輸入或稍後再試。")
        }
    }
}

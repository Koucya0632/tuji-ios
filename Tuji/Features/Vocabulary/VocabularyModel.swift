import Foundation
import Observation

/// One exchange on the AI 查詞 screen: what was asked, and Moira's card once it is
/// back. The conversation is the screen's memory only; 查詞紀錄 is what is kept.
struct VocabularyTurn: Identifiable, Equatable {
    let input: VocabularyInput
    var record: VocabularyRecord?
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
final class VocabularyModel {
    /// The draft in the composer. Sending clears it; the turn keeps what was sent.
    var query: String
    var context = ""
    var selectedSense = ""
    var mode: VocabularyMode = .lookup
    private(set) var offer: VocabularyOffer?
    private(set) var turns: [VocabularyTurn] = []
    /// The turn the conversation should bring into view: a new one, or one
    /// opened from 查詞紀錄. The tick lets the same card be asked for twice.
    private(set) var spotlight: Spotlight?
    private(set) var history: [VocabularyRecord] = []
    private(set) var nextCursor: String?
    private(set) var pending: VocabularyInput?
    private(set) var busy = false
    private(set) var loadingHistory = false
    private(set) var message: String?
    private(set) var historyMessage: String?
    private let repository: VocabularyStudying
    private let language: LanguageContext
    private let identity: ViewerIdentity
    private let journal: VocabularyJournaling
    private let dictionary: LocalDictionaryReading
    private let pollInterval: Duration
    private var owner: String?
    private var scope = ""
    private var historyFavorites = false
    private var historyRequest = UUID()

    struct Spotlight: Equatable {
        let id: String
        let tick: Int
    }

    /// Another card for the newest turn: 助記 offers it as the main action; for
    /// 查詞 and 深度解析 a second card is mostly the same card again, so asking
    /// for one is a quieter choice under the card.
    enum Regeneration: Equatable {
        case main(maxPoints: Int)
        case secondary(maxPoints: Int)
    }

    init(
        query: String = "",
        repository: VocabularyStudying = LiveVocabularyRepository(),
        language: LanguageContext = SettingsStore.shared,
        identity: ViewerIdentity = AuthService.shared,
        journal: VocabularyJournaling = DefaultsVocabularyJournal(),
        dictionary: LocalDictionaryReading = WordsStore.shared,
        pollInterval: Duration = .seconds(2)
    ) {
        self.query = query
        self.repository = repository
        self.language = language
        self.identity = identity
        self.journal = journal
        self.dictionary = dictionary
        self.pollInterval = pollInterval
    }

    var uiLanguage: String {
        UILanguage(code: self.language.uiLang).rawValue
    }

    var learning: String {
        self.language.learningDirection.rawValue
    }

    var target: TargetLanguage {
        self.learning == "zh-ja" ? .ja : .en
    }

    /// 查詞紀錄 is per account and learning direction; the interface language
    /// changes how new cards are explained, not which saved ones are yours.
    var scopeID: String {
        "\(self.identity.uid ?? "")|\(self.learning)"
    }

    var price: VocabularyOffer.Price? {
        self.price(for: self.mode)
    }

    func price(for mode: VocabularyMode) -> VocabularyOffer.Price? {
        self.offer?.modes.first { $0.mode == mode }
    }

    /// Why 送出 cannot be pressed for a reason the person can act on. Input
    /// problems (blank, too long) are said beside the field instead.
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
        guard let price = self.price else { return nil }
        return offer.available < price.maxPoints ? .insufficientPoints : nil
    }

    /// Official 詞條 whose word or Chinese meaning is exactly what was typed — the
    /// free path to point at beside the paid button. 自製 and 物見 cards do not count.
    var catalogMatches: [CardWord] {
        let needle = self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        var seen = Set<String>()
        return self.dictionary.words.filter { word in
            word.id.atlasItemId == nil && word.id.savedCommunitySlug == nil &&
                (word.word.lowercased() == needle || word.chinese.lowercased() == needle) &&
                seen.insert(word.id).inserted
        }
    }

    var canGenerate: Bool {
        let word = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.canSpend(on: self.mode) &&
            !word.isEmpty && word.count <= 120 && word.contains(where: { $0.isLetter || $0.isNumber }) &&
            self.context.count <= 800 && self.selectedSense.count <= 300
    }

    private func canSpend(on mode: VocabularyMode) -> Bool {
        !self.busy && self.pending == nil && self.identity.uid != nil && self.offer?.enabled == true &&
            self.price(for: mode).map { (self.offer?.available ?? 0) >= $0.maxPoints } == true
    }

    /// Only the newest completed card offers another, and only when it can be paid for.
    func regeneration(for turn: VocabularyTurn) -> Regeneration? {
        guard turn.id == self.turns.last?.id, turn.record?.status == .completed,
              self.canSpend(on: turn.input.mode), let price = self.price(for: turn.input.mode)
        else { return nil }
        return turn.input.mode == .mnemonic ? .main(maxPoints: price.maxPoints) :
            .secondary(maxPoints: price.maxPoints)
    }

    func load() async {
        let scope = self.scopeID
        if self.scope != scope {
            self.scope = scope
            self.owner = self.identity.uid
            self.turns = []
            self.spotlight = nil
            self.history = []
            self.nextCursor = nil
            self.pending = nil
            self.offer = nil
            self.busy = false
            self.message = nil
            self.selectedSense = ""
        }
        guard let owner = self.owner else { self.message = tujiLocalized("登入後即可使用 AI 查詞。")
            return
        }
        await self.refreshOffer(scope: scope)
        guard scope == self.scopeID else { return }
        if let input = self.journal.pending(owner: owner)
            .first(where: { $0.learningDirection == self.learning })
        {
            if !self.turns.contains(where: { $0.id == input.requestId }) {
                self.append(VocabularyTurn(input: input))
            }
            self.pending = input
            await self.reconcile()
        }
    }

    private func refreshOffer(scope: String) async {
        do {
            let offer = try await self.repository.offer()
            guard scope == self.scopeID else { return }
            self.offer = offer
        } catch {
            guard scope == self.scopeID else { return }
            self.message = tujiLocalized("暫時無法取得價格，請重新整理。")
        }
    }

    /// The only fresh paid request from the composer. Never called by entry, mode
    /// selection, or a candidate chip — those only fill the draft.
    func generate() async {
        guard self.canGenerate else { return }
        let draft = (
            query: self.query.trimmingCharacters(in: .whitespacesAndNewlines),
            context: self.context.trimmingCharacters(in: .whitespacesAndNewlines),
            sense: self.selectedSense
        )
        self.query = ""
        self.context = ""
        self.selectedSense = ""
        await self.start(mode: self.mode, query: draft.query, context: draft.context, sense: draft.sense)
    }

    /// Another card for what the newest turn asked; a new request, charged again.
    func regenerate(_ turn: VocabularyTurn) async {
        guard self.regeneration(for: turn) != nil else { return }
        await self.start(
            mode: turn.input.mode,
            query: turn.input.query,
            context: turn.input.context,
            sense: turn.input.selectedSense
        )
    }

    private func start(mode: VocabularyMode, query: String, context: String, sense: String) async {
        guard let price = self.price(for: mode), let offer = self.offer, let owner = self.owner else { return }
        let input = VocabularyInput(
            requestId: UUID().uuidString.lowercased(),
            mode: mode,
            query: query,
            context: context,
            selectedSense: sense,
            uiLanguage: self.uiLanguage,
            learningDirection: self.learning,
            pricingVersion: offer.pricingVersion,
            maxPoints: price.maxPoints
        )
        self.journal.save(input, owner: owner)
        self.pending = input
        self.append(VocabularyTurn(input: input))
        await self.send(input, owner: owner, scope: self.scopeID)
    }

    private func send(_ input: VocabularyInput, owner: String, scope: String) async {
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
                await self.refreshOffer(scope: scope)
            } else {
                self.message = tujiLocalized("確認生成結果中，請稍後重試確認。")
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
            await self.send(input, owner: owner, scope: scope)
        } catch {
            guard scope == self.scopeID else { return }
            self.message = tujiLocalized("確認生成結果中，請稍後重試確認。")
        }
    }

    private func poll(_ input: VocabularyInput, owner: String, scope: String) async {
        for _ in 0..<65 {
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

    private func accept(_ record: VocabularyRecord, owner: String) {
        guard record.status != .pending else { return }
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

    /// Puts a candidate into the composer. Spending stays with 送出.
    func choose(_ candidate: VocabularyCandidate, mode: VocabularyMode) {
        self.query = candidate.term
        self.selectedSense = candidate.meaning
        self.mode = mode
        self.message = nil
    }

    func editQuery() {
        self.selectedSense = ""
        self.message = nil
    }

    /// 改一下: what a turn asked goes back into the composer.
    func edit(_ turn: VocabularyTurn) {
        self.query = turn.input.query
        self.context = turn.input.context
        self.selectedSense = turn.input.selectedSense
        self.mode = turn.input.mode
        self.message = nil
    }

    /// A card from 查詞紀錄 joins the conversation once, in whatever language it
    /// was explained in, and is brought into view.
    func open(_ record: VocabularyRecord) {
        guard let input = record.input else { return }
        if self.turns.contains(where: { $0.id == record.id }) {
            self.update(record.id) { $0.record = record }
            self.focus(record.id)
        } else {
            self.append(VocabularyTurn(input: input, record: record))
        }
        self.message = nil
    }

    func loadHistory(favorite: Bool, more: Bool = false) async {
        guard !more || !self.loadingHistory else { return }
        let request = UUID()
        self.historyRequest = request
        self.loadingHistory = true
        self.historyMessage = nil
        let scope = self.scopeID
        defer { if request == self.historyRequest { self.loadingHistory = false } }
        do {
            let list = try await self.repository.records(
                learning: self.learning,
                favorite: favorite,
                cursor: more ? self.nextCursor : nil
            )
            guard scope == self.scopeID, request == self.historyRequest else { return }
            self.historyFavorites = favorite
            self.history = more ? self.history + list.records : list.records
            self.nextCursor = list.nextCursor
        } catch {
            if scope == self.scopeID, request == self.historyRequest {
                self.historyMessage = tujiLocalized("無法讀取查詞紀錄，請重試。")
            }
        }
    }

    func toggleFavorite(_ record: VocabularyRecord) async {
        let scope = self.scopeID
        do {
            let updated = try await self.repository.favorite(id: record.id, value: !record.favorite)
            guard scope == self.scopeID else { return }
            self.update(updated.id) { $0.record = updated }
            self.history = self.history.compactMap { row in
                guard row.id == updated.id else { return row }
                return self.historyFavorites && !updated.favorite ? nil : updated
            }
        } catch {
            guard scope == self.scopeID else { return }
            self.message = tujiLocalized("無法更新書籤，請重試。")
            self.historyMessage = self.message
        }
    }

    func delete(_ record: VocabularyRecord) async {
        let scope = self.scopeID
        do {
            try await self.repository.delete(id: record.id)
            guard scope == self.scopeID else { return }
            self.history.removeAll { $0.id == record.id }
            self.turns.removeAll { $0.id == record.id }
        } catch { self.historyMessage = tujiLocalized("無法刪除紀錄，請重試。") }
    }

    private func append(_ turn: VocabularyTurn) {
        self.turns.append(turn)
        self.focus(turn.id)
    }

    private func focus(_ id: String) {
        self.spotlight = Spotlight(id: id, tick: (self.spotlight?.tick ?? 0) + 1)
    }

    private func update(_ id: String, _ change: (inout VocabularyTurn) -> Void) {
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
        case APIError.unauthorized: tujiLocalized("登入後即可使用 AI 查詞。")
        default: tujiLocalized("目前無法生成，請檢查輸入或稍後再試。")
        }
    }
}

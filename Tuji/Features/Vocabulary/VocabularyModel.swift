import Foundation
import Observation

@MainActor
@Observable
final class VocabularyModel {
    var query: String
    var context = ""
    var selectedSense = ""
    var mode: VocabularyMode = .lookup
    private(set) var offer: VocabularyOffer?
    private(set) var results: [VocabularyRecord] = []
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
    /// A card opened from 查詞紀錄 is shown even when it was explained in another
    /// interface language; a typed query only finds cards made in the current one.
    private var openedID: String?

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
        self.offer?.modes.first { $0.mode == self.mode }
    }

    var current: VocabularyRecord? {
        self.results.last { record in
            guard let input = record.input else { return false }
            return input.mode == self.mode && input.query == self.query
                .trimmingCharacters(in: .whitespacesAndNewlines) &&
                input.context == self.context.trimmingCharacters(in: .whitespacesAndNewlines) &&
                (input.mode == .lookup || input.selectedSense == self.selectedSense) &&
                input.learningDirection == self.learning &&
                (input.uiLanguage == self.uiLanguage || record.id == self.openedID)
        }
    }

    /// Why 生成 cannot be pressed for a reason the person can act on. Input
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

    /// 助記 offers another one as the main action; for 查詞 and 深度解析 a second
    /// card is mostly the same card again, so asking for one is a quieter choice
    /// under the card.
    var regenerationIsSecondary: Bool {
        self.current?.status == .completed && self.mode != .mnemonic
    }

    var canGenerate: Bool {
        let word = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !self.busy && self.pending == nil && self.identity.uid != nil && self.offer?.enabled == true &&
            !word.isEmpty && word.count <= 120 && word.contains(where: { $0.isLetter || $0.isNumber }) &&
            self.context.count <= 800 && self.selectedSense.count <= 300 &&
            self.price.map { (self.offer?.available ?? 0) >= $0.maxPoints } == true
    }

    func load() async {
        let scope = self.scopeID
        if self.scope != scope {
            self.scope = scope
            self.owner = self.identity.uid
            self.results = []
            self.history = []
            self.nextCursor = nil
            self.pending = nil
            self.offer = nil
            self.busy = false
            self.message = nil
            self.selectedSense = ""
            self.openedID = nil
        }
        guard let owner = self.owner else { self.message = tujiLocalized("登入後即可使用 AI 查詞。")
            return
        }
        await self.refreshOffer(scope: scope)
        guard scope == self.scopeID else { return }
        if let input = self.journal.pending(owner: owner)
            .first(where: { $0.learningDirection == self.learning })
        {
            if self.query.isEmpty {
                self.query = input.query
                self.context = input.context
                self.selectedSense = input.selectedSense
                self.mode = input.mode
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

    /// The only fresh paid request. Never called by entry, mode selection, or a lookup chip.
    func generate() async {
        guard self.canGenerate, let price = self.price, let offer = self.offer, let owner = self.owner else { return }
        let input = VocabularyInput(
            requestId: UUID().uuidString.lowercased(),
            mode: self.mode,
            query: self.query.trimmingCharacters(in: .whitespacesAndNewlines),
            context: self.context.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedSense: self.selectedSense,
            uiLanguage: self.uiLanguage,
            learningDirection: self.learning,
            pricingVersion: offer.pricingVersion,
            maxPoints: price.maxPoints
        )
        self.journal.save(input, owner: owner)
        self.pending = input
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
                self.message = Self.failureMessage(error)
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
        self.results.removeAll { $0.id == record.id }
        if record.status != .deleted { self.results.append(record) }
        if record.status == .failed {
            self.message = record.result?.message.isEmpty == false ? record.result?.message :
                (record
                    .error == "insufficient_credits" ? tujiLocalized("罐頭點數不足，這次沒有扣點。") :
                    tujiLocalized("未能生成有效內容，這次沒有扣點。"))
        } else { self.message = nil }
    }

    func choose(_ candidate: VocabularyCandidate, mode: VocabularyMode) {
        self.query = candidate.term
        self.selectedSense = candidate.meaning
        self.mode = mode
        self.message = nil
        self.openedID = nil
    }

    func editQuery() {
        self.selectedSense = ""
        self.message = nil
        self.openedID = nil
    }

    func open(_ record: VocabularyRecord) {
        guard let input = record.input else { return }
        self.query = input.query
        self.context = input.context
        self.selectedSense = input.selectedSense
        self.mode = input.mode
        self.openedID = record.id
        self.results.removeAll { $0.id == record.id }
        self.results.append(record)
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
            let ids = Set(list.records.map(\.id))
            self.results.removeAll { ids.contains($0.id) }
            self.results = (self.results + list.records).sorted { $0.createdAt < $1.createdAt }
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
            self.results = self.results.map { $0.id == updated.id ? updated : $0 }
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
            self.results.removeAll { $0.id == record.id }
        } catch { self.historyMessage = tujiLocalized("無法刪除紀錄，請重試。") }
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

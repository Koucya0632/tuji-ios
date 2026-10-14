// 助手, tier two — the device first, a model only for what the device cannot answer.
//
// 詞條 are still answered by `LocalAssistantResponder`: free, instant, offline.
// When a lookup finds nothing, this responder offers to ask the model instead
// and says what that costs. The question is sent only after the person taps the
// offer — asking spends 罐頭點數, and nothing here spends them on a keyword
// rule's say-so.

import Foundation

@MainActor
final class TieredAssistantResponder: AssistantResponding {
    /// How many catalogue entries travel with a question as grounding, and how
    /// much conversation. Both are the server's limits.
    static let wordLimit = 8
    static let historyLimit = 6

    private let local: AssistantResponding
    private let model: AssistantAsking
    private let dictionary: LocalDictionaryReading
    private let language: LanguageContext
    private let makeRequestId: @MainActor () -> String

    /// The price range and balance, once read. `nil` until a lookup first comes
    /// up empty, and again after a read that failed.
    private var offer: AssistantOffer?
    /// The model's own turns only — what a follow-up question needs.
    private var turns: [AssistantTurn] = []
    /// One id per unanswered question, reused when that question is sent again.
    private var pendingRequestIds: [String: String] = [:]

    init(
        local: AssistantResponding = LocalAssistantResponder(),
        model: AssistantAsking = LiveAssistantRepository(),
        dictionary: LocalDictionaryReading = WordsStore.shared,
        language: LanguageContext = SettingsStore.shared,
        makeRequestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.local = local
        self.model = model
        self.dictionary = dictionary
        self.language = language
        self.makeRequestId = makeRequestId
    }

    func greeting() -> AssistantReply {
        self.local.greeting()
    }

    func reply(toText text: String) async -> AssistantReply? {
        guard let reply = await self.local.reply(toText: text) else { return nil }
        // Only an empty lookup is the device giving up. Every other outcome is
        // an answer, and an answer that is free is not improved by a paid one.
        guard reply.outcome == .noMatch else { return reply }
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // No offer means this account cannot ask (not a 罐頭點數 account, the
        // feature is off, or there is no network): the lookup's own answer stands.
        guard let offer = await self.currentOffer() else { return reply }
        return self.offerReply(for: question, offer: offer, fallback: reply)
    }

    func reply(to intent: AssistantIntent) async -> AssistantReply {
        guard case let .askModel(question) = intent else {
            return await self.local.reply(to: intent)
        }
        return await self.ask(question)
    }

    // MARK: - 報價

    private func currentOffer() async -> AssistantOffer? {
        if let offer { return offer }
        self.offer = try? await self.model.assistantOffer()
        return self.offer
    }

    private func offerReply(for question: String, offer: AssistantOffer, fallback: AssistantReply) -> AssistantReply {
        guard offer.available >= offer.maxPoints else {
            return AssistantReply(
                outcome: .modelInsufficientPoints,
                text: Self.shortOfPoints(offer),
                suggestions: fallback.suggestions
            )
        }
        return AssistantReply(
            outcome: .modelOffer,
            text: Self.priced(offer),
            suggestions: [.askModel(question: question)] + fallback.suggestions
        )
    }

    /// The price is said before the question is sent, never after: a range,
    /// because the exact figure follows the tokens the answer uses.
    private static func priced(_ offer: AssistantOffer) -> String {
        let (low, high, held) = (offer.minPoints, offer.maxPoints, offer.available)
        return tujiLocalized("圖鑑裡沒有這個。要問 AI 嗎？每次回答扣 \(low)–\(high) 點罐頭點數，你現在有 \(held) 點。")
    }

    private static func shortOfPoints(_ offer: AssistantOffer) -> String {
        let (low, high, held) = (offer.minPoints, offer.maxPoints, offer.available)
        return tujiLocalized("圖鑑裡沒有這個。問 AI 每次扣 \(low)–\(high) 點罐頭點數，你現在有 \(held) 點，不夠問一次。")
    }

    // MARK: - 問模型

    private func ask(_ question: String) async -> AssistantReply {
        let requestId = self.pendingRequestIds[question] ?? self.makeRequestId()
        self.pendingRequestIds[question] = requestId
        let payload = AssistantAskPayload(
            requestId: requestId,
            question: question,
            uiLanguage: UILanguage(code: self.language.uiLang).rawValue,
            learningDirection: self.language.learningDirection.rawValue,
            wordIds: Self.candidates(for: question, in: self.dictionary.words).map(\.id),
            history: Array(self.turns.suffix(Self.historyLimit))
        )
        do {
            let answer = try await self.model.askAssistant(payload)
            self.pendingRequestIds[question] = nil
            self.offer = AssistantOffer(
                minPoints: answer.minPoints,
                maxPoints: answer.maxPoints,
                available: answer.available
            )
            return self.reply(for: answer, question: question)
        } catch {
            return self.failureReply(for: error, question: question)
        }
    }

    /// The answer is the sentence and nothing under it. What it cost is on
    /// 點數明細, one tap away, rather than repeated beneath every reply.
    private func reply(for answer: AssistantAnswer, question: String) -> AssistantReply {
        guard answer.inScope else {
            // A declined question is not part of the conversation worth
            // carrying forward, and its (possibly empty) text is replaced.
            return AssistantReply(
                outcome: .modelOutOfScope,
                text: answer.answer.isEmpty
                    ? tujiLocalized("我只能幫忙語言學習的問題。這次沒有扣點。")
                    : answer.answer,
                suggestions: [.lookupPrompt]
            )
        }
        self.turns.append(AssistantTurn(role: .user, text: Self.clipped(question)))
        self.turns.append(AssistantTurn(role: .assistant, text: Self.clipped(answer.answer)))
        self.turns = Array(self.turns.suffix(Self.historyLimit))
        return AssistantReply(outcome: .modelAnswer, text: answer.answer)
    }

    /// Every failure says the same true thing — nothing was charged — and keeps
    /// the question one tap away, under the same request id.
    private func failureReply(for error: Error, question: String) -> AssistantReply {
        let retry: [AssistantIntent] = [.askModel(question: question)]
        switch error {
        case let APIError.conflict(reason, _) where reason == "insufficient_credits":
            self.offer = nil
            return AssistantReply(
                outcome: .modelInsufficientPoints,
                text: tujiLocalized("罐頭點數不夠問這一次。沒有扣點。"),
                suggestions: [.lookupPrompt]
            )
        case APIError.rateLimited:
            return AssistantReply(
                outcome: .modelBusy,
                text: tujiLocalized("問得有點快，等一下再問我。沒有扣點。"),
                suggestions: retry
            )
        case APIError.transport:
            return AssistantReply(
                outcome: .modelOffline,
                text: tujiLocalized("連不上網路，問不到 AI。沒有扣點。"),
                suggestions: retry
            )
        case APIError.forbidden, APIError.notFound, APIError.unauthorized:
            self.offer = nil
            return AssistantReply(
                outcome: .modelUnavailable,
                text: tujiLocalized("現在不能問 AI。沒有扣點。"),
                suggestions: [.lookupPrompt]
            )
        default:
            return AssistantReply(
                outcome: .modelUnavailable,
                text: tujiLocalized("AI 現在沒有回應，等一下再試。沒有扣點。"),
                suggestions: retry
            )
        }
    }

    // MARK: - 附帶的詞條

    /// Catalogue words the question mentions, longest mention first.
    ///
    /// Only public entries: the server reads these ids from its own catalogue,
    /// and 自製圖鑑 (`atlas:`) and 物見 (`saved:`) ids are not in it.
    static func candidates(for question: String, in words: [CardWord]) -> [CardWord] {
        let needle = question.lowercased()
        let tokens = Set(needle.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return words
            .compactMap { word -> (word: CardWord, length: Int)? in
                guard word.id.atlasItemId == nil, word.id.savedCommunitySlug == nil else { return nil }
                let lengths = [word.word, word.chinese].compactMap { Self.mention(of: $0, in: needle, tokens: tokens) }
                return lengths.max().map { (word, $0) }
            }
            .sorted { $0.length != $1.length ? $0.length > $1.length : $0.word.id < $1.word.id }
            .prefix(Self.wordLimit)
            .map(\.word)
    }

    /// How long the mention is, or nil when the question does not mention it.
    /// A Latin term has to be a whole word (`pan` is not in `Japan`); a CJK one
    /// needs two characters, since a single kanji is in half of everything.
    private static func mention(of term: String, in needle: String, tokens: Set<String>) -> Int? {
        let term = term.lowercased().trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return nil }
        if term.allSatisfy(\.isASCII) {
            let found = term.contains(" ") ? needle.contains(term) : tokens.contains(term)
            return found ? term.count : nil
        }
        return needle.contains(term) ? term.count : nil
    }

    /// The server caps a history turn at 600 characters.
    private static func clipped(_ text: String) -> String {
        String(text.prefix(600))
    }
}

// 助手, tier one — answers from the data the app already has.
//
// The dictionary is in memory from launch, so every answer is a filter over
// it: instant, offline, and free.

import Foundation

@MainActor
final class LocalAssistantResponder: AssistantResponding {
    /// How many rows a reply shows before it points at the full list. A chat
    /// bubble is not a results page.
    static let previewLimit = 6

    private let dictionary: LocalDictionaryReading

    init(dictionary: LocalDictionaryReading = WordsStore.shared) {
        self.dictionary = dictionary
    }

    func greeting() -> AssistantReply {
        AssistantReply(
            outcome: .greeting,
            text: tujiLocalized("嗨，我可以幫你查圖鑑裡的詞。想找什麼？"),
            suggestions: [.lookupPrompt]
        )
    }

    func reply(toText text: String) async -> AssistantReply? {
        guard let intent = AssistantIntent.parse(text) else { return nil }
        return await self.reply(to: intent)
    }

    func reply(to intent: AssistantIntent) async -> AssistantReply {
        switch intent {
        case .lookupPrompt: self.lookupPromptReply()
        case let .lookup(query): self.lookupReply(query: query)
        // This responder holds no model. `TieredAssistantResponder` answers
        // this intent before it gets here.
        case .askModel:
            AssistantReply(
                outcome: .modelUnavailable,
                text: tujiLocalized("現在不能問 AI。沒有扣點。"),
                suggestions: [.lookupPrompt]
            )
        }
    }

    // MARK: - 詞條

    private func lookupPromptReply() -> AssistantReply {
        AssistantReply(
            outcome: .lookupPrompt,
            text: tujiLocalized("把想查的字打給我，用中文或正在學的語言都可以。")
        )
    }

    private func lookupReply(query: String) -> AssistantReply {
        // The ranking 搜尋 already owns — one answer to "what matches this".
        let matches = SearchVM.localMatches(query, in: self.dictionary.words)
        guard !matches.isEmpty else {
            return AssistantReply(
                outcome: .noMatch,
                text: tujiLocalized("圖鑑裡還沒有「\(query)」。試試用中文查，或換個說法。"),
                suggestions: [.lookupPrompt]
            )
        }
        return AssistantReply(
            outcome: .words,
            text: tujiLocalized("找到 \(matches.count) 個跟「\(query)」有關的詞。"),
            attachment: Self.preview(matches, more: .search(query: query))
        )
    }

    private static func preview(_ words: [CardWord], more: NavRoute?) -> AssistantReply.Attachment {
        .words(
            Array(words.prefix(previewLimit)),
            total: words.count,
            more: words.count > previewLimit ? more : nil
        )
    }
}

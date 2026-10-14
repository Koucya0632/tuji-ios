// 助手 — one answer: a sentence, what it found, and what to ask next.
//
// A value, so "what did it decide" is asked without a screen. `outcome` is the
// decision and `text` is that decision in the interface language — tests pin
// the first, because CI reads English and a laptop reads 繁體中文.

import Foundation

struct AssistantReply: Equatable {
    enum Outcome: Equatable {
        case greeting
        case words
        case noMatch
        case lookupPrompt
        /// Lookup found nothing; the model can be asked, for a price.
        case modelOffer
        case modelAnswer
        /// The model declined: not a language-learning question. Not charged.
        case modelOutOfScope
        case modelInsufficientPoints
        case modelBusy
        case modelOffline
        case modelUnavailable
    }

    enum Attachment: Equatable {
        /// `total` is how many there are; `words` is the few shown. `more` is
        /// where the rest live, when there is such a place.
        case words([CardWord], total: Int, more: NavRoute?)
    }

    let outcome: Outcome
    /// Already resolved against the interface language — a `String` does not
    /// follow uiLang by itself the way a `LocalizedStringKey` does.
    let text: String
    var attachment: Attachment?
    var suggestions: [AssistantIntent] = []
}

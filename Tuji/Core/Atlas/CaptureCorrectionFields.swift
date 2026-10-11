// 校正欄位 — what the capture correction form asks the user for, given the
// interface language and the language they are learning.
//
// The question was answered twice, in two vocabularies, in two places that no
// single test could reach. `AtlasCaptureView` asked whether the capture was
// *monolingual* to decide which second field to draw; `AtlasCaptureVM` asked
// whether it *needed a separate gloss* to decide whether a cached candidate was
// incomplete and worth one repair call. Over the same {UILanguage ×
// TargetLanguage} grid they are exact complements — and one of them lived in a
// `View` computed property, which is where the app has been bitten before
// (CONTEXT.md: `CompletionReadout.ratio` had five copies and two skipped the
// clamp; `language(in:)` was documented as the caller's job and 11 of 13 callers
// never did it).
//
// One grid, one home, and `needsGloss` is *derived from* the field rather than
// stated beside it, so the two cannot drift apart again.

import Foundation

/// The second field on the correction form — the one that carries the meaning.
/// The first is always 圖片名稱 (`lemma`).
enum CaptureSecondField: String, Equatable {
    /// Chinese interfaces edit `displayZhHant` directly.
    case chineseName
    /// A ja/en interface learning the *other* language edits their-language
    /// gloss. `displayZhHant` still rides through as the Chinese base column.
    case gloss
    /// UI language == target language. The lemma is already in the user's own
    /// language and the definition is generated, so there is no useful meaning
    /// left to hand-enter.
    case hidden
}

enum CaptureCorrectionFields {
    static func second(ui: UILanguage, target: TargetLanguage) -> CaptureSecondField {
        switch ui {
        case .zhHant, .zhHans: .chineseName
        case .ja: target == .ja ? .hidden : .gloss
        case .en: target == .en ? .hidden : .gloss
        }
    }

    /// The language a recognition should also name its candidates in — the one
    /// the gloss field is edited in — or nil when the form has no gloss field.
    /// Asked on the way into a paid quote; it used to be restated in a `View`.
    static func glossLanguage(ui: UILanguage, target: TargetLanguage) -> String? {
        self.second(ui: ui, target: target) == .gloss ? ui.rawValue : nil
    }

    /// The meaning a candidate chip shows under its label: whatever the form's
    /// second field would hold. A ja/en interface never falls back to the
    /// Chinese name — it is not this user's language, and it is not on the form.
    static func candidateMeaning(second: CaptureSecondField, zhHant: String?, gloss: String?) -> String? {
        let value: String? = switch second {
        case .chineseName: zhHant
        case .gloss: gloss
        case .hidden: nil
        }
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// The Chinese name a confirm sends, or nil to send none.
    ///
    /// Without the Chinese field on screen the user cannot correct it, so once
    /// they rename the card the candidate's Chinese name describes the object
    /// they corrected away from. The server regenerates it from the new name.
    static func chineseNameToSend(
        second: CaptureSecondField,
        lemma: String,
        suggestedLemma: String?,
        zhHant: String
    )
        -> String?
    {
        guard second != .chineseName, let suggestedLemma else { return zhHant }
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trim(lemma) == trim(suggestedLemma) ? zhHant : nil
    }
}

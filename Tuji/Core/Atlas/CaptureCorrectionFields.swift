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
enum CaptureSecondField: Equatable {
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

    /// Whether the model is expected to return a UI-language gloss for this
    /// capture — which is the same question as "does the form have a gloss field
    /// to fill", and so is answered by asking it.
    static func needsGloss(ui: UILanguage, target: TargetLanguage) -> Bool {
        self.second(ui: ui, target: target) == .gloss
    }
}

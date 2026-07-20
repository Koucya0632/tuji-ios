// Single source of truth for the app's interface languages. Raw values are
// the wire codes shared with tuji-web (lib/settings.ts UI_LANGS) — the value
// set is pinned by UILanguageTests, and adding a language is a coordinated
// client+server change (the server clamps unknown codes back to zh-Hant).
//
// Interface language only: orthogonal to LearningDirection (the language
// being studied). Study content stays Chinese-glossed for every case — see
// `contentLanguageCode`.
//
// `nonisolated`: pure value enum used from nonisolated contexts (the
// `tujiLocalized` fallback) under the project's MainActor default isolation.

import Foundation

nonisolated enum UILanguage: String, CaseIterable {
    case zhHant = "zh-Hant" // declaration order = picker display order
    case zhHans = "zh-Hans"
    case ja
    case en

    /// Resolves a wire/persisted code, mapping unknown, legacy, or missing
    /// codes to the zh-Hant default (mirrors the server's clamp).
    init(code: String?) {
        self = code.flatMap(UILanguage.init(rawValue:)) ?? .zhHant
    }

    /// The SwiftUI environment locale that drives `Text(LocalizedStringKey)`
    /// catalog lookup (see TujiApp).
    var locale: Locale {
        Locale(identifier: self.rawValue)
    }

    /// Display name in the language itself. Deliberately never localized —
    /// each picker row must stay readable to a speaker of that language.
    var nativeName: String {
        switch self {
        case .zhHant: "繁體中文"
        case .zhHans: "简体中文"
        case .ja: "日本語"
        case .en: "English"
        }
    }

    /// `lang` query value for server *content* endpoints (/api/words,
    /// /api/categories, word detail). Study-content glosses follow the UI
    /// language, so this is just the wire code — the server picks the gloss
    /// language (ja/en definitions, zh-Hant base, or OpenCC zh-Hans).
    var contentLanguageCode: String {
        self.rawValue
    }

    /// First-run default: the first supported language in the device's
    /// preferred-language list. Resolved once per launch.
    static let deviceDefault = detect(from: Locale.preferredLanguages)

    /// Scans the ordered BCP-47 tags and returns the first supported
    /// language (Bundle.preferredLocalizations semantics: unsupported tags
    /// are skipped, not treated as a miss). Falls back to zh-Hant.
    ///
    /// Parses via `Locale.Language.Components`, which keeps exactly the
    /// subtags present — `Locale.Language` would likely-subtag-infer bare
    /// "zh" into Hans, but this product's Chinese default is Traditional.
    static func detect(from preferredLanguages: [String]) -> UILanguage {
        for tag in preferredLanguages {
            let language = Locale.Language.Components(identifier: tag)
            guard let code = language.languageCode else { continue }
            switch code {
            case .japanese:
                return .ja
            case .english:
                return .en
            case .chinese:
                if language.script == .hanSimplified { return .zhHans }
                if language.script == .hanTraditional { return .zhHant }
                // No explicit script: CN/SG write Simplified; TW/HK/MO and
                // bare "zh" default to Traditional.
                return language.region == .chinaMainland || language.region == .singapore
                    ? .zhHans
                    : .zhHant
            default:
                continue
            }
        }
        return .zhHant
    }
}

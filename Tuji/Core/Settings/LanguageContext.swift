import Foundation

/// The slice of the user's live settings a repository needs to language-scope a
/// request: the in-app UI language and the learning direction. A narrow read
/// seam (per ADR-0001) so a repository test substitutes a two-line stub instead
/// of standing up a whole `SettingsStore`.
///
/// Read live at call time on purpose — an in-app language/direction switch must
/// take effect on the very next request, not wait for the debounced server sync.
@MainActor
protocol LanguageContext {
    var uiLang: String { get }
    var learningDirection: LearningDirection { get }
}

extension SettingsStore: LanguageContext {
    var uiLang: String {
        self.current.uiLang
    }

    var learningDirection: LearningDirection {
        self.current.learningDirection
    }
}

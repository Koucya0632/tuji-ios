// Bringing the localized catalog up to date for whoever is about to see it.
//
// `LaunchCoordinator` is deep in *sequencing* — the minimum splash beat, the
// catalog generation handover, cancelling superseded work, tracking `appOpen`
// once — and all of that is tested. What it was not deep in is *content*: its
// interface was eight closures, and every one of their bodies lived in
// `TujiApp.init`, where nothing can reach them. Two of the eight were the same
// eight lines twice, differing only in the two fields `CatalogContext`'s own
// precondition exists to relate:
//
//     preloadCatalog   → userID nil,      includePersonalization false
//     finalizeSignedIn → userID非 nil,     includePersonalization true
//
// So "what a launch actually loads" was an anonymous closure in an `@main`
// struct: not searchable by name, not callable from a test, and duplicated. This
// is the read-side shape `AccumulationWarmer` already has, applied to the one
// path that never got it.

import Foundation

/// Who the catalog snapshot is for.
///
/// The distinction is part of the request's *identity*, not a flag on it: launch
/// may begin an anonymous preload before authentication resolves and then ask
/// for the signed-in user's custom/saved words under otherwise identical
/// language settings, and those two must never share an in-flight result.
enum CatalogAudience: Equatable {
    case guest
    case signedIn(userID: UUID)

    var userID: UUID? {
        switch self {
        case .guest: nil
        case let .signedIn(userID): userID
        }
    }

    /// Only a signed-in audience gets custom + saved words folded in.
    /// `CatalogContext` refuses the combination the other way round.
    var includesPersonalization: Bool {
        self.userID != nil
    }

    /// The catalog request identity for this audience.
    ///
    /// Pure, and separate from the fan-out below, because this is the half that
    /// was written twice: the two closures differed only in the two fields set
    /// here, and `CatalogContext`'s precondition exists to relate exactly those
    /// two. A pure function is also the only part of a launch a test can ask
    /// about without standing up three stores.
    func context(settings: UserSettings) -> CatalogContext {
        CatalogContext(
            settings: settings,
            userID: self.userID,
            includePersonalization: self.includesPersonalization
        )
    }
}

@MainActor
protocol CatalogWarming {
    /// Bring words + categories up to date for this audience, and return once
    /// they are both current. Idempotent: every store behind it is
    /// context-keyed, so a repeat for the same audience is a no-op.
    func warm(for audience: CatalogAudience) async
}

/// The live adapter. The only place that knows which stores make up "the
/// catalog", the same way `LiveAtlasMutationRefresher` is the only place that
/// knows what a 圖鑑 mutation refreshes.
@MainActor
struct LiveCatalogWarmer: CatalogWarming {
    private let settings: SettingsStore
    private let words: WordsStore
    private let categories: CategoriesStore

    init(
        settings: SettingsStore = .shared,
        words: WordsStore = .shared,
        categories: CategoriesStore = .shared
    ) {
        self.settings = settings
        self.words = words
        self.categories = categories
    }

    func warm(for audience: CatalogAudience) async {
        // Settings first and alone for a signed-in audience: the catalog context
        // is *derived* from them, so loading them alongside the catalog would
        // race the request against its own parameters. A guest has no stored
        // settings to wait for, which is the whole reason the two paths differ.
        if let userID = audience.userID {
            await self.settings.loadIfNeeded(for: userID)
        }
        let context = audience.context(settings: self.settings.current)
        async let words: Void = self.words.loadIfNeeded(for: context)
        async let categories: Void = self.categories.loadIfNeeded(for: context)
        _ = await (words, categories)
    }
}

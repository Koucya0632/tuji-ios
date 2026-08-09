import Foundation

/// Immutable request identity for the localized catalog snapshot.
///
/// `includePersonalization` is deliberately part of the identity: launch may
/// begin an anonymous preload before authentication resolves, then request the
/// signed-in user's custom/saved words for otherwise identical language
/// settings. Those requests must never share an in-flight result.
struct CatalogContext: Hashable {
    let contentLanguageCode: String
    let learningDirectionCode: String
    let userID: UUID?
    let includePersonalization: Bool

    init(
        contentLanguageCode: String,
        learningDirectionCode: String,
        userID: UUID? = nil,
        includePersonalization: Bool = false
    ) {
        precondition(
            !includePersonalization || userID != nil,
            "Personalized catalog loads require a user identity"
        )
        self.contentLanguageCode = contentLanguageCode
        self.learningDirectionCode = learningDirectionCode
        self.userID = userID
        self.includePersonalization = includePersonalization
    }

    init(settings: UserSettings, userID: UUID?, includePersonalization: Bool) {
        self.init(
            contentLanguageCode: settings.uiLanguage.contentLanguageCode,
            learningDirectionCode: settings.learningDirection.rawValue,
            userID: userID,
            includePersonalization: includePersonalization
        )
    }

    /// Compatibility snapshot for existing feature-level Store calls. Launch
    /// coordination should prefer the explicit initializer so authentication
    /// and settings are captured once for both WordsStore and CategoriesStore.
    @MainActor
    static func current(includePersonalization: Bool? = nil) -> CatalogContext {
        let userID: UUID? = if case let .signedIn(user) = AuthService.shared.state {
            user.id
        } else {
            nil
        }
        return CatalogContext(
            settings: SettingsStore.shared.current,
            userID: userID,
            includePersonalization: includePersonalization ?? (userID != nil)
        )
    }
}

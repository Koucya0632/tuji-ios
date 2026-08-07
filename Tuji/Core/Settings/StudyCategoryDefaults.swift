import Foundation

/// What a brand-new selection of study themes contains, in one place.
///
/// It used to be split: `newUserCategoryIDs` here held only the two personal
/// atlas themes, and the beginner trio lived privately in `SetupView`. A signed
/// -in user came out fine because Setup unions the two — but **a guest never
/// runs Setup**, so their entire selection was 自定義 + 物見: two themes a guest
/// can never fill, because a guest can neither photograph nor 收進圖鑑. That
/// left 設定 claiming 「已選 2 個」 next to a 主題進度 counted over the whole
/// dictionary.
enum StudyCategoryDefaults {
    static let customID = "custom"
    static let communityID = "community"

    /// The personal atlas themes: worth having ticked from the first launch,
    /// even while still empty, so anything the user makes or saves lands
    /// somewhere they are already studying.
    static let atlasCategoryIDs = [customID, communityID]

    /// Hand-picked opening themes. Concrete, indoor, and well populated, so a
    /// new account has real cards on day one.
    static let beginnerCategoryIDs = ["kitchen", "bathroom", "living-room"]

    /// The pre-server default (`UserSettings.default`), and therefore the whole
    /// of a guest's selection. Must contain themes that actually hold words.
    static let newUserCategoryIDs = beginnerCategoryIDs + atlasCategoryIDs

    static func addingCommunity(to categoryIDs: [String]) -> [String] {
        Array(Set(categoryIDs).union([communityID])).sorted()
    }
}

/// One-time, per-account migration for people whose settings predate the
/// 物見 study theme. Keeping the marker per account avoids one user's
/// migration suppressing it for another account on the same device.
struct CommunityStudyCategoryMigration {
    private let defaults: UserDefaults
    private let keyPrefix = "tuji.settings.communityStudyCategory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasApplied(for userID: UUID) -> Bool {
        self.defaults.bool(forKey: self.key(for: userID))
    }

    func migrated(_ settings: UserSettings) -> UserSettings {
        var migrated = settings
        migrated.studyCategories = StudyCategoryDefaults.addingCommunity(
            to: settings.studyCategories
        )
        return migrated
    }

    func markApplied(for userID: UUID) {
        self.defaults.set(true, forKey: self.key(for: userID))
    }

    private func key(for userID: UUID) -> String {
        "\(self.keyPrefix).\(userID.uuidString)"
    }
}

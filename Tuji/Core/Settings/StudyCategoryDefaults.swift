import Foundation

/// What a brand-new selection of study themes contains, in one place.
///
/// It used to be split: `newUserCategoryIDs` here held only the two personal
/// atlas themes, and the beginner trio lived privately in `SetupView`, so
/// anything that read the default before Setup ran saw 自定義 + 物見 alone: two
/// themes that start empty, with 設定 claiming 「已選 2 個」 next to a 主題進度
/// counted over the whole dictionary.
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

    /// The pre-server default (`UserSettings.default`). Must contain themes
    /// that actually hold words.
    static let newUserCategoryIDs = beginnerCategoryIDs + atlasCategoryIDs

    static func addingCommunity(to categoryIDs: [String]) -> [String] {
        Array(Set(categoryIDs).union([communityID])).sorted()
    }

    /// The themes that actually get studied: the user's pick, narrowed to what
    /// the server says this account may study (`Membership.studyableCategories`).
    ///
    /// Nil gate keeps the pick. A gated pick narrows to allowed themes; when
    /// none remain, hidden-region IDs stay nonempty so they cannot accidentally
    /// expand to all free themes. Visible-only locked selections retain the
    /// existing free-theme fallback; unknown visibility stays conservative.
    static func effective(selected: [String], studyable: [String]?, visibleCategoryIDs: Set<String>? = nil) -> [String] {
        guard let studyable else { return selected }
        let allowed = Set(studyable)
        let kept = selected.filter { allowed.contains($0) }
        if !kept.isEmpty { return kept }
        if !selected.isEmpty {
            guard let visibleCategoryIDs else { return selected }
            let hidden = selected.filter { !visibleCategoryIDs.contains($0) }
            if !hidden.isEmpty { return hidden }
        }
        return studyable.sorted()
    }

    /// The server's list for whoever is signed in; nil before the first
    /// entitlement sync, for members, and under policy v1.
    static var liveStudyable: [String]? {
        AtlasStore.shared.entitlement?.membership?.studyableCategories
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

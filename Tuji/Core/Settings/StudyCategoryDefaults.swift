import Foundation

/// The personal atlas themes that are useful from the first launch, even
/// before the user has created or saved any words in them.
enum StudyCategoryDefaults {
    static let customID = "custom"
    static let communityID = "community"
    static let newUserCategoryIDs = [customID, communityID]

    static func addingCommunity(to categoryIDs: [String]) -> [String] {
        Array(Set(categoryIDs).union([communityID])).sorted()
    }
}

/// One-time, per-account migration for people whose settings predate the
/// 社群圖鑑 study theme. Keeping the marker per account avoids one user's
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

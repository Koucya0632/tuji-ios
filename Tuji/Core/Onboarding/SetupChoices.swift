// What 「先幫你排一份學習節奏」 starts from.
//
// `setupDone` is a flag on *this device*, so an account that finished Setup on
// its old phone runs it again on a new one — or after a reinstall. Setup used to
// start from the beginner trio every time and POST a whole settings object
// built from literals (`accent: "us"`, `showZh: true`, `fontSize: "md"`), so one
// tap on 完成設定 replaced the account's themes, goal and accent with a new
// user's.
//
// Whether the account has already been set up is readable from the account
// itself: the server hands a new account an empty theme list, and Setup cannot
// finish without at least one theme.

import Foundation

struct SetupChoices: Equatable {
    var topicIds: Set<String>
    var dailyGoal: Int

    /// - Parameters:
    ///   - account: the account's settings, when they have arrived for this
    ///     account; nil otherwise.
    ///   - catalogIds: the themes that exist, so a retired id is not preselected.
    static func seed(account: UserSettings?, catalogIds: Set<String>, firstThemesFallback: [String]) -> SetupChoices {
        if let account {
            let existing = Set(account.studyCategories).intersection(catalogIds)
            if !existing.isEmpty {
                return SetupChoices(topicIds: existing, dailyGoal: account.dailyGoal)
            }
        }
        let atlas = Set(StudyCategoryDefaults.atlasCategoryIDs).intersection(catalogIds)
        let beginner = StudyCategoryDefaults.beginnerCategoryIDs.filter { catalogIds.contains($0) }
        let opening = beginner.count == StudyCategoryDefaults.beginnerCategoryIDs.count
            ? Set(beginner)
            : Set(firstThemesFallback.prefix(3))
        return SetupChoices(topicIds: opening.union(atlas), dailyGoal: UserSettings.default.dailyGoal)
    }
}

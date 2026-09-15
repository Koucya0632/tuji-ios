import Testing
@testable import Tuji

/// What Setup starts from — see `SetupChoices`.
struct SetupChoicesTests {
    private let catalog: Set<String> = ["kitchen", "bathroom", "living-room", "office", "street", "custom", "community"]
    private let order = ["kitchen", "bathroom", "living-room", "office", "street", "custom", "community"]

    /// The defect: `setupDone` is per device, so an account that set up on its
    /// old phone was handed the beginner trio on its new one.
    @Test
    func aReturningAccountStartsFromItsOwnThemesAndGoal() {
        var account = UserSettings.default
        account.studyCategories = ["office", "street"]
        account.dailyGoal = 30

        let seed = SetupChoices.seed(account: account, catalogIds: self.catalog, firstThemesFallback: self.order)

        #expect(seed.topicIds == ["office", "street"])
        #expect(seed.dailyGoal == 30)
    }

    /// The server hands a new account an empty theme list.
    @Test
    func aNewAccountStartsFromTheBeginnerThemes() {
        var account = UserSettings.default
        account.studyCategories = []

        let seed = SetupChoices.seed(account: account, catalogIds: self.catalog, firstThemesFallback: self.order)

        #expect(seed.topicIds == ["kitchen", "bathroom", "living-room", "custom", "community"])
    }

    @Test
    func settingsThatHaveNotArrivedAreNotTreatedAsTheAccounts() {
        let seed = SetupChoices.seed(account: nil, catalogIds: self.catalog, firstThemesFallback: self.order)
        #expect(seed.topicIds.contains("kitchen"))
        #expect(seed.dailyGoal == UserSettings.default.dailyGoal)
    }

    @Test
    func retiredThemesAreNotPreselected() {
        var account = UserSettings.default
        account.studyCategories = ["retired-theme"]

        let seed = SetupChoices.seed(account: account, catalogIds: self.catalog, firstThemesFallback: self.order)

        #expect(!seed.topicIds.contains("retired-theme"))
        #expect(seed.topicIds.contains("kitchen"))
    }
}

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

        let seed = SetupChoices.seed(
            account: account,
            catalogIds: self.catalog,
            presets: [],
            firstThemesFallback: self.order
        )

        #expect(seed.topicIds == ["office", "street"])
        #expect(seed.dailyGoal == 30)
    }

    /// The server hands a new account an empty theme list. With no 主題組合
    /// (an older backend), the beginner trio is still the opening.
    @Test
    func aNewAccountWithNoPresetsStartsFromTheBeginnerThemes() {
        var account = UserSettings.default
        account.studyCategories = []

        let seed = SetupChoices.seed(
            account: account,
            catalogIds: self.catalog,
            presets: [],
            firstThemesFallback: self.order
        )

        #expect(seed.topicIds == ["kitchen", "bathroom", "living-room", "custom", "community"])
    }

    @Test
    func settingsThatHaveNotArrivedAreNotTreatedAsTheAccounts() {
        let seed = SetupChoices.seed(
            account: nil,
            catalogIds: self.catalog,
            presets: [],
            firstThemesFallback: self.order
        )
        #expect(seed.topicIds.contains("kitchen"))
        #expect(seed.dailyGoal == UserSettings.default.dailyGoal)
    }

    @Test
    func retiredThemesAreNotPreselected() {
        var account = UserSettings.default
        account.studyCategories = ["retired-theme"]

        let seed = SetupChoices.seed(
            account: account,
            catalogIds: self.catalog,
            presets: [],
            firstThemesFallback: self.order
        )

        #expect(!seed.topicIds.contains("retired-theme"))
        #expect(seed.topicIds.contains("kitchen"))
    }

    // MARK: - 主題組合 (ADR-0020)

    private let student = TopicPreset(id: "student", name: "留學生", categoryIds: ["office", "street"], isDefault: true)
    private let travel = TopicPreset(id: "travel", name: "旅遊", categoryIds: ["kitchen"], isDefault: false)

    /// The default is the flagged preset, not the first one in the list.
    @Test
    func aNewAccountStartsFromTheDefaultPresetPlusTheSources() {
        var account = UserSettings.default
        account.studyCategories = []

        let seed = SetupChoices.seed(
            account: account,
            catalogIds: self.catalog,
            presets: [self.travel, self.student],
            firstThemesFallback: self.order
        )

        #expect(seed.topicIds == ["office", "street", "custom", "community"])
    }

    @Test
    func aReturningAccountIgnoresTheDefaultPreset() {
        var account = UserSettings.default
        account.studyCategories = ["bathroom"]

        let seed = SetupChoices.seed(
            account: account,
            catalogIds: self.catalog,
            presets: [self.student],
            firstThemesFallback: self.order
        )

        #expect(seed.topicIds == ["bathroom"])
    }

    /// A default preset whose themes are all gone falls back rather than
    /// leaving the account with only the (empty) sources.
    @Test
    func aDefaultPresetWithNoThemesInTheCatalogFallsBack() {
        let gone = TopicPreset(id: "student", name: "留學生", categoryIds: ["retired-theme"], isDefault: true)

        let seed = SetupChoices.seed(
            account: nil,
            catalogIds: self.catalog,
            presets: [gone],
            firstThemesFallback: self.order
        )

        #expect(seed.topicIds == ["kitchen", "bathroom", "living-room", "custom", "community"])
    }
}

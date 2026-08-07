import Foundation
import Testing
@testable import Tuji

struct StudyCategoryDefaultsTests {
    @Test
    func firstLaunchDefaultsIncludePersonalAtlasThemes() {
        #expect(
            UserSettings.default.studyCategories
                == ["kitchen", "bathroom", "living-room", "custom", "community"]
        )
    }

    /// A guest never runs `SetupView`, so `UserSettings.default` *is* their
    /// whole selection. It used to be 自定義 + 物見 alone — two themes a guest
    /// can never fill, since a guest can neither photograph nor 收進圖鑑 — which
    /// left 設定 saying 「已選 2 個」 beside a 主題進度 counted over the entire
    /// dictionary. The default has to carry themes that actually hold words.
    @Test
    func firstLaunchDefaultsAreNotAllEmptyAtlasThemes() {
        let defaults = UserSettings.default.studyCategories
        let dictionaryThemes = defaults.filter {
            !StudyCategoryDefaults.atlasCategoryIDs.contains($0)
        }
        #expect(!dictionaryThemes.isEmpty)
        #expect(dictionaryThemes == StudyCategoryDefaults.beginnerCategoryIDs)
    }

    @Test
    func migrationAddsOnlyCommunityAndPreservesExistingThemes() {
        var settings = UserSettings.default
        settings.studyCategories = ["kitchen", "custom"]

        let migrated = CommunityStudyCategoryMigration().migrated(settings)

        #expect(migrated.studyCategories == ["community", "custom", "kitchen"])
    }

    @Test
    func appliedMigrationDoesNotRunAgainAfterManualRemoval() throws {
        let suiteName = "StudyCategoryDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let migration = CommunityStudyCategoryMigration(defaults: defaults)
        let userID = UUID()

        #expect(!migration.hasApplied(for: userID))
        migration.markApplied(for: userID)
        #expect(migration.hasApplied(for: userID))

        var manuallyChanged = UserSettings.default
        manuallyChanged.studyCategories = ["kitchen"]
        if !migration.hasApplied(for: userID) {
            manuallyChanged = migration.migrated(manuallyChanged)
        }

        #expect(manuallyChanged.studyCategories == ["kitchen"])
    }

    @Test
    func migrationMarkerIsScopedPerAccount() throws {
        let suiteName = "StudyCategoryDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let migration = CommunityStudyCategoryMigration(defaults: defaults)
        let firstUserID = UUID()
        let secondUserID = UUID()

        migration.markApplied(for: firstUserID)

        #expect(migration.hasApplied(for: firstUserID))
        #expect(!migration.hasApplied(for: secondUserID))
    }
}

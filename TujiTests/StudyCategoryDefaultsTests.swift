import Foundation
import Testing
@testable import Tuji

struct StudyCategoryDefaultsTests {
    @Test
    func firstLaunchDefaultsIncludePersonalAtlasThemes() {
        #expect(UserSettings.default.studyCategories == ["custom", "community"])
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

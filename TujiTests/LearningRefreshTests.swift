import Testing
@testable import Tuji

/// `LearningRefresh`: what each cause re-reads, and the order it does it in.
@MainActor
struct LearningRefreshTests {
    // MARK: - The policy

    /// The drift that made this module: the prompt says 「將刪除掌握度」, and the
    /// View handed the clear `[progress, studyStats]`.
    @Test
    func clearingProgressRereadsEverythingTheWipeEmptied() {
        #expect(LearningRefreshCause.progressCleared.targets == [.progress, .stats, .mastery, .queue])
    }

    /// 我 · 進度 draws the 熟練度 bar; its pull used to re-read progress alone.
    @Test
    func pullingMeRereadsMasteryToo() {
        #expect(LearningRefreshCause.pulledMe(isGuest: false).targets == [.progress, .mastery])
    }

    @Test
    func pullingTodayDropsTheQueueAlongWithTheNumbers() {
        #expect(LearningRefreshCause.pulledToday(isGuest: false).targets
            == [.progress, .stats, .mastery, .queue, .dictionary, .themes])
    }

    @Test
    func aGuestHasNoAccountStoresToRefresh() {
        #expect(LearningRefreshCause.pulledToday(isGuest: true).targets == [.dictionary, .themes])
        #expect(LearningRefreshCause.pulledMe(isGuest: true).targets.isEmpty)
    }

    @Test
    func theInterfaceLanguageRereadsOnlyTheCatalogue() {
        #expect(LearningRefreshCause.uiLanguageChanged.targets == [.dictionary, .themes])
    }

    // MARK: - The glue

    /// Invalidate first, then re-read. Re-reading a store that still holds its
    /// pre-wipe copy refills it with what was there.
    @Test
    func everyStoreIsInvalidatedBeforeAnyIsReread() async {
        let log = RefreshLog()
        let refresher = LiveLearningRefresher(
            learningStore: { target in
                switch target {
                case .progress: SpyStore(name: "progress", log: log)
                case .stats: SpyStore(name: "stats", log: log)
                case .mastery: SpyStore(name: "mastery", log: log)
                case .queue, .dictionary, .themes: nil
                }
            },
            invalidateQueue: { log.entries.append("queue.invalidate") },
            reloadDictionary: { log.entries.append("dictionary.reload") },
            reloadThemes: { log.entries.append("themes.reload") }
        )

        await refresher.refresh(after: .progressCleared)

        let invalidations = ["progress.invalidate", "stats.invalidate", "mastery.invalidate", "queue.invalidate"]
        #expect(Set(log.entries.prefix(4)) == Set(invalidations))
        #expect(Set(log.entries.dropFirst(4)) == ["progress.reload", "stats.reload", "mastery.reload"])
        #expect(!log.entries.contains("dictionary.reload"))
    }

    @Test
    func theCatalogueIsRereadInPlaceNotDropped() async {
        let log = RefreshLog()
        let refresher = LiveLearningRefresher(
            learningStore: { _ in nil },
            invalidateQueue: { log.entries.append("queue.invalidate") },
            reloadDictionary: { log.entries.append("dictionary.reload") },
            reloadThemes: { log.entries.append("themes.reload") }
        )

        await refresher.refresh(after: .uiLanguageChanged)

        #expect(Set(log.entries) == ["dictionary.reload", "themes.reload"])
    }
}

@MainActor
private final class RefreshLog {
    var entries: [String] = []
}

@MainActor
private final class SpyStore: RefreshableStore {
    let name: String
    let log: RefreshLog

    init(name: String, log: RefreshLog) {
        self.name = name
        self.log = log
    }

    func invalidate() {
        self.log.entries.append("\(self.name).invalidate")
    }

    func reload() async {
        self.log.entries.append("\(self.name).reload")
    }
}

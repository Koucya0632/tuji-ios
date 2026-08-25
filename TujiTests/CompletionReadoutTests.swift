// Pins 完成度 — the seen/total/ratio rule that 首頁's hero and 我's completion
// card now share.
//
// Each of the first three tests is a case where the two screens used to
// disagree, because 我 carried its own copy of the rule from before the
// denominator fix and without a guest branch at all.

import Testing
@testable import Tuji

struct CompletionReadoutTests {
    private func inputs(
        isGuest: Bool = false,
        settingsLoaded: Bool = true,
        studyCategories: [String] = ["kitchen"],
        guestLearnedCount: Int = 0,
        seenInSelection: Int = 40,
        totalInSelection: Int = 120,
        dictionaryCount: Int = 480,
        dictionaryCountInSelection: Int = 60
    )
        -> CompletionReadout.Inputs
    {
        CompletionReadout.Inputs(
            isGuest: isGuest,
            settingsLoaded: settingsLoaded,
            studyCategories: studyCategories,
            guestLearnedCount: guestLearnedCount,
            seenInSelection: seenInSelection,
            totalInSelection: totalInSelection,
            dictionaryCount: dictionaryCount,
            dictionaryCountInSelection: dictionaryCountInSelection
        )
    }

    // MARK: - The three divergences

    @Test("a guest's progress is the local learned set, not the empty server rows")
    func guestCountsWhatIsOnTheDevice() {
        // 我 used to read the server's seen count for guests — always 0 — and
        // print 「0% · 已學 0 / 共 480 字」 to someone 首頁 credited with 37.
        let readout = CompletionReadout(
            self.inputs(
                isGuest: true,
                studyCategories: [],
                guestLearnedCount: 37,
                seenInSelection: 0,
                totalInSelection: 0
            )
        )
        #expect(readout.seen == 37)
        #expect(readout.total == 480)
    }

    @Test("the denominator describes the selection, not the whole dictionary")
    func fallbackStaysWithinTheSelection() {
        // Themes that hold no published cards (自定義 + 物見): the server has
        // no rows, so the fallback runs. It must stay scoped.
        let readout = CompletionReadout(
            self.inputs(
                studyCategories: ["custom", "community"],
                seenInSelection: 0,
                totalInSelection: 0,
                dictionaryCountInSelection: 12
            )
        )
        #expect(readout.total == 12)
        #expect(readout.scope == .selectedThemes)
    }

    @Test("with no themes picked the fraction reads 0/0, not a whole-catalog number")
    func noSelectionIsPending() {
        let readout = CompletionReadout(
            self.inputs(studyCategories: [], seenInSelection: 300, totalInSelection: 480)
        )
        #expect(readout.seen == 0)
        #expect(readout.total == 0)
        #expect(readout.scope == .pending)
        #expect(readout.percent == 0)
    }

    // MARK: - Fallback ladder

    @Test("the server's count wins whenever it has one")
    func serverTotalWins() {
        let readout = CompletionReadout(self.inputs())
        #expect(readout.seen == 40)
        #expect(readout.total == 120)
    }

    @Test("the whole dictionary stands in only when nothing is selected")
    func wholeDictionaryOnlyWithoutASelection() {
        // Settings have not arrived, so an empty theme list means nothing yet —
        // this is not the 選擇主題 prompt, it is "we don't know".
        let readout = CompletionReadout(
            self.inputs(
                settingsLoaded: false,
                studyCategories: [],
                seenInSelection: 0,
                totalInSelection: 0
            )
        )
        #expect(readout.total == 480)
        #expect(readout.scope == .wholeDictionary)
    }

    // MARK: - Ratio

    @Test("a withdrawn word can leave seen > total, and the ratio still stops at 1")
    func ratioClamps() {
        // seen counts studied words; total counts *published* cards. Two of the
        // four hand-written copies of this expression skipped the clamp, which
        // printed 「103%」 beside a bar pinned at full.
        let readout = CompletionReadout(
            self.inputs(seenInSelection: 124, totalInSelection: 120)
        )
        #expect(readout.ratio == 1)
        #expect(readout.percent == 100)
    }

    @Test("a zero denominator is zero, not a division by zero")
    func ratioIsZeroSafe() {
        #expect(CompletionReadout.ratio(seen: 0, total: 0) == 0)
        #expect(CompletionReadout.ratio(seen: 5, total: 0) == 0)
    }

    @Test("the percentage is derived from the ratio, so it cannot disagree with the bar")
    func percentFollowsRatio() {
        let readout = CompletionReadout(
            self.inputs(seenInSelection: 40, totalInSelection: 120)
        )
        #expect(readout.percent == 33)
        #expect(readout.ratio == CompletionReadout.ratio(seen: 40, total: 120))
    }

    // MARK: - Theme prompt

    @Test("an empty theme list only means 'pick themes' once settings have loaded")
    func themePromptWaitsForSettings() {
        #expect(
            !CompletionReadout(self.inputs(settingsLoaded: false, studyCategories: []))
                .showsThemePrompt
        )
        #expect(
            CompletionReadout(self.inputs(settingsLoaded: true, studyCategories: []))
                .showsThemePrompt
        )
    }

    @Test("a guest is never prompted to pick themes")
    func guestsAreNotPrompted() {
        let readout = CompletionReadout(self.inputs(isGuest: true, studyCategories: []))
        #expect(!readout.showsThemePrompt)
    }
}

// MARK: - The mapping

/// Pins the *reading* — the six stores → the eight facts — which used to be
/// hand-written three times: 首頁 assembling `TodayDecisions.Inputs`,
/// `TodayDecisions` copying eight of its eleven fields across again, and 我
/// assembling its own set from the same stores. Two of the three lived in `View`
/// bodies, so nothing could check that the two screens asked the same question.
/// They once did not: `isGuest` had two answers and agreed only by accident.
@MainActor
struct CompletionInputsMappingTests {
    private func word(_ id: String, category: String) -> CardWord {
        CardWord(
            id: id,
            word: id,
            chinese: "",
            imageUrl: "",
            category: category,
            pronunciation: "",
            reading: nil
        )
    }

    private func makeProgress(_ rows: [CategoryProgress]) async -> ProgressStore {
        let repo = MappingProgressRepository(rows: rows)
        let store = ProgressStore(repository: repo)
        await store.reload()
        return store
    }

    private func makeWords(_ words: [CardWord]) async -> WordsStore {
        let repo = MappingCatalogRepository(words: words)
        let store = WordsStore(repository: repo)
        await store.reload(for: CatalogContext(
            contentLanguageCode: "zh-Hant",
            learningDirectionCode: "zh-en"
        ))
        return store
    }

    /// The selection is the filter for all four scoped numbers. Words and
    /// progress rows outside the picked themes must not reach the denominator —
    /// this is the bug the module was built around, and it now has a test on the
    /// *reading* rather than only on the rule.
    @Test
    func everyScopedNumberIsMeasuredAgainstTheSameSelection() async {
        let progress = await self.makeProgress([
            CategoryProgress(category: "kitchen", total: 30, seen: 12),
            CategoryProgress(category: "office", total: 50, seen: 40)
        ])
        let words = await self.makeWords([
            self.word("a", category: "kitchen"),
            self.word("b", category: "kitchen"),
            self.word("c", category: "office")
        ])

        let inputs = CompletionReadout.Inputs(
            viewer: FakeViewer(isGuest: false),
            settings: FakeStudySelection(studyCategories: ["kitchen"]),
            progress: progress,
            words: words,
            cache: FakeGuestProgress(learnedCount: 0)
        )

        #expect(inputs.studyCategories == ["kitchen"])
        #expect(inputs.seenInSelection == 12)
        #expect(inputs.totalInSelection == 30)
        #expect(inputs.dictionaryCountInSelection == 2)
        // The unscoped one stays unscoped — it is the denominator for "no themes
        // picked", and nothing else.
        #expect(inputs.dictionaryCount == 3)
    }

    /// `isGuest` comes from the viewer seam and nowhere else. It decides whether
    /// 完成度 counts the local learned set or the server rows, and it is the one
    /// field the two screens once answered differently.
    @Test
    func isGuestComesFromTheViewer() async {
        let progress = await self.makeProgress([])
        let words = await self.makeWords([])

        for guest in [true, false] {
            let inputs = CompletionReadout.Inputs(
                viewer: FakeViewer(isGuest: guest),
                settings: FakeStudySelection(studyCategories: []),
                progress: progress,
                words: words,
                cache: FakeGuestProgress(learnedCount: 7)
            )
            #expect(inputs.isGuest == guest)
            // Read regardless of who is looking: the *rule* decides when it is
            // used, so the reading must not pre-empt it.
            #expect(inputs.guestLearnedCount == 7)
        }
    }

    /// An empty theme list before settings arrive is not a selection — it is an
    /// unanswered question, and the two are one field apart.
    @Test
    func settingsLoadedTravelsWithTheSelection() async {
        let progress = await self.makeProgress([])
        let words = await self.makeWords([])

        let cold = CompletionReadout.Inputs(
            viewer: FakeViewer(isGuest: false),
            settings: FakeStudySelection(studyCategories: [], settingsLoaded: false),
            progress: progress,
            words: words,
            cache: FakeGuestProgress(learnedCount: 0)
        )
        #expect(!cold.settingsLoaded)
        #expect(!CompletionReadout(cold).showsThemePrompt)

        let warm = CompletionReadout.Inputs(
            viewer: FakeViewer(isGuest: false),
            settings: FakeStudySelection(studyCategories: [], settingsLoaded: true),
            progress: progress,
            words: words,
            cache: FakeGuestProgress(learnedCount: 0)
        )
        #expect(warm.settingsLoaded)
        #expect(CompletionReadout(warm).showsThemePrompt)
    }

    /// 首頁 composes the same input set rather than restating it — the eight
    /// fields it used to copy across field by field are now one value.
    @Test
    func todayComposesTheSameInputsRatherThanRestatingThem() async {
        let progress = await self.makeProgress([
            CategoryProgress(category: "kitchen", total: 30, seen: 12)
        ])
        let words = await self.makeWords([self.word("a", category: "kitchen")])
        let shared = CompletionReadout.Inputs(
            viewer: FakeViewer(isGuest: false),
            settings: FakeStudySelection(studyCategories: ["kitchen"]),
            progress: progress,
            words: words,
            cache: FakeGuestProgress(learnedCount: 0)
        )

        let today = TodayDecisions(
            .init(completion: shared, dailyGoal: 10, stats: nil, progressLoaded: true)
        )

        #expect(today.completion == CompletionReadout(shared))
    }
}

// MARK: - Mapping fakes

@MainActor
private struct FakeViewer: ViewerIdentity {
    var isGuest: Bool
    var uid: String? {
        nil
    }

    var authorRef: AtlasAuthorRef? {
        nil
    }

    func owns(handle _: String) -> Bool {
        false
    }

    func displayName(fallback: String) -> String {
        fallback
    }
}

@MainActor
private struct FakeStudySelection: StudySelectionReading {
    var studyCategories: [String]
    var settingsLoaded: Bool = true
}

@MainActor
private struct FakeGuestProgress: GuestProgressReading {
    var learnedCount: Int
}

@MainActor
private final class MappingProgressRepository: ProgressRepository {
    private let rows: [CategoryProgress]

    init(rows: [CategoryProgress]) {
        self.rows = rows
    }

    func loadProgress() async throws -> ProgressResponse {
        ProgressResponse(
            streak: StudyStreak(
                current: 0,
                longest: 0,
                totalDays: 0,
                todayCount: 0,
                lastStudyDate: nil
            ),
            heatmap: nil,
            categories: self.rows
        )
    }

    func clearProgress() async throws {}
    func loadMastery() async throws -> MasteryListResponse {
        MasteryListResponse(items: [])
    }

    func loadTopWords(type _: String, limit _: Int) async throws -> TopWordsResponse {
        TopWordsResponse(words: [], type: nil)
    }

    func toggleFavorite(wordId _: String, isFavorite _: Bool) async {}
}

@MainActor
private final class MappingCatalogRepository: CatalogRepository {
    private let words: [CardWord]

    init(words: [CardWord]) {
        self.words = words
    }

    struct NotImplemented: Error {}

    func loadWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        WordsListResponse(words: self.words, total: self.words.count)
    }

    func loadCategories(lang _: String) async throws -> CategoriesResponse {
        throw NotImplemented()
    }

    func loadCustomWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        throw NotImplemented()
    }

    func loadSavedWords(lang _: String, learning _: String) async throws -> WordsListResponse {
        throw NotImplemented()
    }

    func search(_: String) async throws -> SearchResponse {
        throw NotImplemented()
    }

    func word(id _: String, lang _: String, learning _: String) async throws -> Word {
        throw NotImplemented()
    }
}

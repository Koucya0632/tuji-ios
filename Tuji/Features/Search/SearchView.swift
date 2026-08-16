// Search (§III.J).
//
// Local-first: the full dictionary already lives in WordsStore, so every
// keystroke filters in-memory and shows results instantly (works offline,
// no debounce wait). In parallel a debounced GET /api/search runs to
// supplement with matches the local list can't see (synonyms / also-known-
// as / fuzzy); its results are merged in + deduped when they arrive.
// While the field is empty, surface LocalCache.recentSearches. Tapping a
// result pushes WordDetailView. Tapping a recent search re-runs the query.

import OSLog
import Observation
import SwiftUI

@MainActor
@Observable
final class SearchVM {
    var query: String = ""
    var results: [CardWord] = []
    var loading: Bool = false
    var lastError: Error?
    var lastQuery: String = ""

    private var task: Task<Void, Never>?
    private let repository: CatalogRepository
    private let log = Logger(subsystem: "app.tuji.ios", category: "search")

    init(repository: CatalogRepository = LiveCatalogRepository.shared) {
        self.repository = repository
    }

    func updateQuery(_ q: String) {
        self.query = q
        self.task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            self.results = []
            self.lastError = nil
            self.lastQuery = ""
            self.loading = false
            return
        }
        // Instant local results — no waiting on the network.
        self.results = Self.localMatches(trimmed, in: WordsStore.shared.words)
        self.lastQuery = trimmed
        self.lastError = nil
        // Debounced server search to supplement the local hits.
        self.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runSearch(trimmed)
        }
    }

    /// Re-run a known query immediately (no debounce) — used when the user
    /// taps a "recent searches" row.
    func runImmediately(_ q: String) {
        self.task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        self.query = q
        self.results = Self.localMatches(trimmed, in: WordsStore.shared.words)
        self.lastQuery = trimmed
        self.lastError = nil
        Task { await self.runSearch(trimmed) }
    }

    private func runSearch(_ q: String) async {
        self.loading = true
        defer { self.loading = false }
        do {
            let resp = try await self.repository.search(q)
            // Drop a stale response if the user kept typing mid-flight.
            guard q == self.query.trimmingCharacters(in: .whitespaces) else { return }
            self.results = Self.merge(
                local: Self.localMatches(q, in: WordsStore.shared.words),
                remote: resp.results
            )
            self.lastQuery = q
            self.lastError = nil
            self.log.info(
                "search '\(q, privacy: .public)' → \(self.results.count, privacy: .public) results"
            )
            if !self.results.isEmpty {
                LocalCache.shared.pushRecentSearch(q)
            }
        } catch {
            guard q == self.query.trimmingCharacters(in: .whitespaces) else { return }
            // Keep the instant local results on screen; only surface the
            // error when there's nothing to show.
            if self.results.isEmpty {
                self.lastError = error
            }
            self.log.error(
                "search '\(q, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Matching

    /// Case-insensitive ranked match over the supplied dictionary (callers pass
    /// WordsStore's in-memory list; injected so the ranking is unit-testable).
    /// Looks at English word, Chinese gloss, and pronunciation. Closer matches
    /// (exact → prefix → contains) and shorter words sort first.
    static func localMatches(_ q: String, in words: [CardWord]) -> [CardWord] {
        let needle = q.lowercased()
        guard !needle.isEmpty else { return [] }
        return words
            .compactMap { w -> (word: CardWord, rank: Int)? in
                let word = w.word.lowercased()
                let zh = w.chinese.lowercased()
                let pron = w.pronunciation.lowercased()
                let reading = w.reading?.lowercased() ?? ""
                let rank: Int
                if word == needle { rank = 0 }
                else if word.hasPrefix(needle) { rank = 1 }
                else if zh.hasPrefix(needle) { rank = 2 }
                else if word.contains(needle) { rank = 3 }
                else if zh.contains(needle) { rank = 4 }
                else if reading.contains(needle) { rank = 5 }
                else if pron.contains(needle) { rank = 6 }
                else { return nil }
                return (w, rank)
            }
            .sorted { a, b in
                a.rank != b.rank ? a.rank < b.rank : a.word.word.count < b.word.word.count
            }
            .map(\.word)
    }

    /// Local hits first (already ranked), then any remote-only matches,
    /// deduped by id.
    static func merge(local: [CardWord], remote: [CardWord]) -> [CardWord] {
        var seen = Set<String>()
        var out: [CardWord] = []
        for w in local + remote where seen.insert(w.id).inserted {
            out.append(w)
        }
        return out
    }
}

struct SearchView: View {
    @Environment(LocalCache.self) private var cache
    @Environment(StudyFocus.self) private var studyFocus
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// Prefills the field for `tuji://search?q=...` deep links; nil for the
    /// normal empty-search entry point (magnifying-glass icon).
    var initialQuery: String?

    @State private var vm = SearchVM()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.tujiPaper.ignoresSafeArea()
            VStack(spacing: 0) {
                self.searchBar
                self.content
                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Reuse the study-focus flag so MainTabsView hides its custom tab
        // bar (and frees the 78pt reservation) while searching.
        .onAppear {
            self.studyFocus.enter()
            self.fieldFocused = true
            if let initialQuery, !initialQuery.trimmingCharacters(in: .whitespaces).isEmpty,
               self.vm.query.isEmpty
            {
                self.vm.updateQuery(initialQuery)
            }
        }
        .onDisappear { self.studyFocus.exit() }
    }

    // MARK: - Bits

    /// The capsule search field is the single most recognisable iOS component
    /// there is, so the field becomes a square-cornered block of `tujiPaper2` —
    /// a hole in the paper rather than an outline drawn on it. The old hairline
    /// border on a `tujiPaper` ground was invisible against the page anyway.
    private var searchBar: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tujiInk2)
                TextField(
                    self.settings.current.learningDirection == .zhJa
                        ? "搜尋日文 / 假名 / 中文"
                        : "搜尋英文 / 中文",
                    text: Binding(
                        get: { self.vm.query },
                        set: { self.vm.updateQuery($0) }
                    )
                )
                .focused(self.$fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk)
                .tint(.tujiInk)
                if !self.vm.query.isEmpty {
                    Button {
                        self.vm.updateQuery("")
                        self.fieldFocused = true
                    } label: {
                        // A bare ✕, not `xmark.circle.fill` — the grey filled
                        // disc is iOS's own clear button, and it is the second
                        // thing that gave this field away as a system control.
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.tujiInk2)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("清除"))
                }
            }
            .padding(.leading, Space.s3)
            .padding(.trailing, Space.s1)
            .frame(height: 52)
            .background(.tujiPaper2)
            .overlay {
                if self.fieldFocused {
                    Rectangle().stroke(.tujiCurrent, lineWidth: Border.bw2)
                }
            }
            .animation(Motion.ease(Motion.d1), value: self.fieldFocused)

            TujiNavTextAction(title: "取消") { self.dismiss() }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = self.vm.query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self.recentSection
        } else if self.vm.loading, self.vm.results.isEmpty {
            self.loadingState
        } else if let error = self.vm.lastError, self.vm.results.isEmpty {
            self.errorState(error)
        } else if self.vm.results.isEmpty, !self.vm.lastQuery.isEmpty {
            self.emptyState(query: trimmed)
        } else {
            self.resultsList
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if self.cache.recentSearches.isEmpty {
            MascotEmptyState(
                pose: .sleep,
                title: "找個單字試試",
                message: "輸入英文或中文，即時顯示結果"
            )
            .tujiEmptyStatePlacement()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        // Section labels are 墨3, not teal. Teal marks
                        // accumulation; a heading accumulates nothing.
                        Text("最近搜尋")
                            .font(.tujiLabel)
                            .tracking(0.5)
                            .foregroundStyle(.tujiInk3)
                        Spacer()
                        TujiNavTextAction(title: "清除全部") {
                            self.cache.clearRecentSearches()
                        }
                    }
                    .padding(.horizontal, Space.s4)

                    ForEach(Array(self.cache.recentSearches.enumerated()), id: \.element) { index, q in
                        if index > 0 {
                            Rectangle()
                                .fill(.tujiRule)
                                .frame(height: Border.bw1)
                                .padding(.leading, Space.s4)
                        }
                        Button {
                            self.vm.runImmediately(q)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Text(q)
                                    .font(.tujiBody)
                                    .foregroundStyle(.tujiInk)
                                    .lineLimit(1)
                                Spacer(minLength: Space.s2)
                                // Points up-left into the field it will refill,
                                // so it reads as "put this back" rather than as
                                // another row that pushes a screen.
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.tujiInk3)
                            }
                            .padding(.horizontal, Space.s4)
                            .frame(height: 56)
                            .contentShape(.rect)
                        }
                        .tujiRowStyle()
                    }
                }
                .padding(.top, Space.s3)
            }
        }
    }

    /// Skeleton rows, not a spinner: results are about to occupy this space, and
    /// showing their shape is more honest than a bar that says only "wait".
    private var loadingState: some View {
        TujiSkeletonRows(count: 3, height: 88)
            .padding(.top, Space.s2)
    }

    private func emptyState(query: String) -> some View {
        MascotEmptyState(
            pose: .sleep,
            title: "找不到「\(query)」",
            // Names the one thing that most often works, rather than telling
            // the user to go and think of a better word themselves.
            message: "試試看用中文查"
        )
        .tujiEmptyStatePlacement()
    }

    private func errorState(_ error: Error) -> some View {
        VStack {
            Spacer(minLength: Space.s5)
            TujiErrorState(
                title: "搜尋失敗",
                message: error.localizedDescription
            ) {
                BBtn(title: "重試", fullWidth: false, action: {
                    self.vm.runImmediately(self.vm.query)
                })
            }
            Spacer(minLength: Space.s5)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s4)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    Text("\(self.vm.results.count) 個結果")
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(.tujiInk3)
                    if self.vm.loading {
                        TujiProgressBar(progress: nil).frame(width: 40)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s3)

                ForEach(Array(self.vm.results.enumerated()), id: \.element.id) { index, word in
                    if index > 0 {
                        Rectangle()
                            .fill(.tujiRule)
                            .frame(height: Border.bw1)
                            .padding(.leading, Space.s4)
                    }
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        SearchResultRow(word: word, query: self.vm.lastQuery)
                    }
                    .tujiRowStyle()
                }
            }
            .padding(.bottom, Space.s5)
        }
    }
}

private struct SearchResultRow: View {
    let word: CardWord
    var query: String = ""

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: Space.s3) {
            self.thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(self.highlighted(self.word.word))
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if self.settings.current.showZh {
                    Text(self.highlighted(self.word.chinese))
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s2)
            TujiRowAccessory()
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 88)
        .contentShape(.rect)
    }

    /// The container holds the square and the picture fills it, so a portrait
    /// cut-out cannot make its own row taller than its neighbours' — and the
    /// `tujiPaper2` ground plus multiply dissolves the white backdrop these
    /// dictionary cut-outs ship with, which used to sit on the page as a
    /// visibly whiter rectangle.
    private var thumbnail: some View {
        Color.tujiPaper2
            .frame(width: 56, height: 56)
            .overlay {
                WordPicture(
                    url: self.word.imageURL,
                    kind: self.word.imageKind,
                    inset: Space.s1,
                    glyphSize: 16
                )
            }
            .clipped()
    }

    /// Marks the matched substring with a 瞳黃 ground rather than teal text.
    /// Teal now means accumulation, and a recoloured glyph is hard to pick out
    /// mid-sentence in CJK — a highlighter mark is the system's way of saying
    /// "this is the part you asked for". Case-insensitive; no-op when nothing
    /// matches (server hits often match a synonym that isn't in the label).
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let needle = self.query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty,
              let range = attr.range(of: needle, options: .caseInsensitive)
        else { return attr }
        attr[range].backgroundColor = .tujiCurrent
        attr[range].foregroundColor = .tujiInk
        return attr
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .environment(LocalCache.shared)
            .environment(StudyFocus.shared)
    }
}

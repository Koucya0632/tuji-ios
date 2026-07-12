// Search (§III.J).
//
// Local-first: the full dictionary already lives in WordsStore, so every
// keystroke filters in-memory and shows results instantly (works offline,
// no debounce wait). In parallel a debounced GET /api/search runs to
// supplement with matches the local list can't see (synonyms / also-known-
// as / fuzzy); its results are merged in + deduped when they arrive.
// While the field is empty, surface LocalCache.recentSearches. Tapping a
// result pushes WordDetailView. Tapping a recent search re-runs the query.

import Nuke
import NukeUI
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
    var initialQuery: String? = nil

    @State private var vm = SearchVM()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.tujiBg.ignoresSafeArea()
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

    private var searchBar: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
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
                .tint(.tujiTeal)
                if !self.vm.query.isEmpty {
                    Button {
                        self.vm.updateQuery("")
                        self.fieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tujiInk4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(.tujiCard, in: .capsule)
            .overlay(Capsule().stroke(.tujiInk4.opacity(0.3), lineWidth: 1))

            Button {
                self.dismiss()
            } label: {
                Text("取消")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiTeal)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
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
            VStack {
                Spacer(minLength: Space.s8)
                MascotEmptyState(
                    pose: .think,
                    title: "找個單字試試",
                    message: "輸入英文或中文，即時顯示結果"
                )
                Spacer(minLength: Space.s8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.s6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text("最近搜尋")
                            .font(.tujiOverline)
                            .tracking(2)
                            .foregroundStyle(.tujiTeal)
                        Spacer()
                        Button {
                            self.cache.clearRecentSearches()
                        } label: {
                            Text("清除全部")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tujiInk3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, Space.s2)
                    ForEach(self.cache.recentSearches, id: \.self) { q in
                        Button {
                            self.vm.runImmediately(q)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.tujiInk4)
                                Text(q)
                                    .font(.tujiBody)
                                    .foregroundStyle(.tujiInk)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tujiInk4)
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().background(.tujiInk4.opacity(0.15))
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s4)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            Spacer().frame(height: Space.s12)
            ProgressView().tint(.tujiTeal)
            Text("搜尋中…")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyState(query: String) -> some View {
        VStack {
            Spacer(minLength: Space.s8)
            MascotEmptyState(
                pose: .think,
                title: "找不到「\(query)」",
                message: "換個關鍵字試試，或瀏覽圖鑑"
            )
            Spacer(minLength: Space.s8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s6)
    }

    private func errorState(_ error: Error) -> some View {
        VStack {
            Spacer(minLength: Space.s8)
            MascotEmptyState(
                pose: .think,
                title: "搜尋失敗",
                message: "\(error.localizedDescription)"
            ) {
                BBtn(title: "重試", fullWidth: false, action: {
                    self.vm.runImmediately(self.vm.query)
                })
            }
            Spacer(minLength: Space.s8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s6)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Text("\(self.vm.results.count) 個結果")
                        .font(.tujiOverline)
                        .tracking(2)
                        .foregroundStyle(.tujiInk3)
                    if self.vm.loading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.tujiTeal)
                    }
                }
                .padding(.top, Space.s2)
                ForEach(self.vm.results) { word in
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        SearchResultRow(word: word, query: self.vm.lastQuery)
                    }
                    .buttonStyle(.plain)
                    Divider().background(.tujiInk4.opacity(0.15))
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s8)
        }
    }
}

private struct SearchResultRow: View {
    let word: CardWord
    var query: String = ""

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(.tujiBg)
                LazyImage(url: self.word.imageURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(Space.s1)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(self.highlighted(self.word.word))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                if self.settings.current.showZh {
                    Text(self.highlighted(self.word.chinese))
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.vertical, Space.s2)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    /// Tints the matched substring teal so the user can see why a result
    /// surfaced. Case-insensitive; no-op when nothing matches.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let needle = self.query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty,
              let range = attr.range(of: needle, options: .caseInsensitive)
        else { return attr }
        attr[range].foregroundColor = .tujiTeal
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

// Search (§III.J).
//
// Debounced (250ms) text field → GET /api/search?q=. While the field is
// empty, surface LocalCache.recentSearches. Tapping a result pushes
// WordDetailView. Tapping a recent search re-runs the query.

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
    private let log = Logger(subsystem: "app.tuji.ios", category: "search")

    func updateQuery(_ q: String) {
        self.query = q
        self.task?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            self.results = []
            self.lastError = nil
            self.lastQuery = ""
            return
        }
        self.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runSearch(trimmed)
        }
    }

    /// Re-run the search immediately (no debounce) for a known query —
    /// used when the user taps a "recent searches" row.
    func runImmediately(_ q: String) {
        self.task?.cancel()
        self.query = q
        Task { await self.runSearch(q) }
    }

    private func runSearch(_ q: String) async {
        self.loading = true
        self.lastError = nil
        defer { self.loading = false }
        do {
            let resp: SearchResponse = try await APIClient.shared.get(.search(q: q))
            // Guard against a race where the user typed a new query
            // mid-flight — drop the stale response.
            guard q == self.query.trimmingCharacters(in: .whitespaces) else { return }
            self.results = resp.results
            self.lastQuery = q
            self.log.info(
                "search '\(q, privacy: .public)' → \(resp.results.count, privacy: .public) results"
            )
            if !resp.results.isEmpty {
                LocalCache.shared.pushRecentSearch(q)
            }
        } catch {
            self.lastError = error
            self.log.error(
                "search '\(q, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

struct SearchResponse: Decodable {
    let results: [CardWord]
    let query: String?
    let limit: Int?
}

struct SearchView: View {
    @Environment(LocalCache.self) private var cache
    @Environment(\.dismiss) private var dismiss

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
        .onAppear { self.fieldFocused = true }
    }

    // MARK: - Bits

    private var searchBar: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.tujiInk3)
                TextField("搜尋單字 / 中文", text: Binding(
                    get: { self.vm.query },
                    set: { self.vm.updateQuery($0) }
                ))
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
                    .font(.system(size: 15, weight: .heavy))
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
        } else if let error = self.vm.lastError {
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
            VStack(spacing: Space.s3) {
                Spacer().frame(height: Space.s12)
                Mascot(pose: .think, size: 80)
                Text("找個單字試試")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text("輸入英文或中文，按空白鍵自動搜尋")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.s6)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
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
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.tujiInk3)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(self.cache.recentSearches, id: \.self) { q in
                        Button {
                            self.vm.runImmediately(q)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.tujiInk4)
                                Text(q)
                                    .font(.tujiBody)
                                    .foregroundStyle(.tujiInk)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(.tujiInk4)
                            }
                            .padding(.vertical, Space.s3)
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
        VStack(spacing: Space.s3) {
            Spacer().frame(height: Space.s12)
            Mascot(pose: .think, size: 80)
            Text("找不到「\(query)」")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text("換個關鍵字試試，或瀏覽圖鑑")
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s6)
    }

    private func errorState(_ error: Error) -> some View {
        VStack(spacing: Space.s3) {
            Spacer().frame(height: Space.s12)
            Mascot(pose: .think, size: 80)
            Text("搜尋失敗")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text(error.localizedDescription)
                .font(.tujiCaption)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s6)
            BBtn(title: "重試", fullWidth: false, action: {
                self.vm.runImmediately(self.vm.query)
            })
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("\(self.vm.results.count) 個結果")
                    .font(.tujiOverline)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
                    .padding(.top, Space.s2)
                ForEach(self.vm.results) { word in
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        SearchResultRow(word: word)
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

    var body: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(.tujiTealSoft)
                Image(systemName: "textformat.abc")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.tujiTeal)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.word.word)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                Text(self.word.chinese)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.vertical, Space.s3)
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .environment(LocalCache.shared)
    }
}

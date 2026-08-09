// Per-word detail page (§III.H).
//
// Loads the full Word from GET /api/words/{id} the first time it appears.
// Sections render conditionally — etymology / examples / forms /
// collocations may all be empty for some words.

import Nuke
import NukeUI
import SwiftUI

/// Pushed entry point. Hosts a horizontally-paged TabView so the user can
/// swipe left/right between adjacent words in the 圖鑑, without popping back
/// to the grid. The page sequence is the full word list in store order
/// (same order as the 全部 grid); we open centred on the tapped word.
///
/// All full-screen chrome (hide the tab bar via study-focus, hidden nav
/// bar, bottom inset) lives here once, so swiping between pages doesn't
/// churn the StudyFocus counter or re-evaluate the inset per word.
struct WordDetailView: View {
    let id: String

    @Environment(StudyFocus.self) private var studyFocus
    @Environment(WordsStore.self) private var wordsStore

    @State private var currentId: String?

    init(id: String) {
        self.id = id
        _currentId = State(initialValue: id)
    }

    /// Ordered ids to page through. Falls back to just this word if the
    /// store hasn't loaded yet or the id isn't in it, so the page always
    /// renders something.
    private var ids: [String] {
        let all = self.wordsStore.words.map(\.id)
        return all.contains(self.id) ? all : [self.id]
    }

    var body: some View {
        TabView(selection: self.$currentId) {
            ForEach(self.ids, id: \.self) { wid in
                WordDetailPage(id: wid)
                    .tag(wid as String?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.tujiPaper)
        .toolbar(.hidden, for: .navigationBar)
        // Hide the custom TujiTabBar on this full-screen detail page by
        // entering study-focus (MainTabsView watches this flag). While the
        // bar is hidden there's nothing to reserve space for, so the local
        // bottom inset collapses to 0; the 78pt fallback only applies if
        // the bar were ever visible here.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: self.studyFocus.active ? 0 : 78)
        }
        .onAppear { self.studyFocus.enter() }
        .onDisappear { self.studyFocus.exit() }
        // Ensure the dictionary is loaded so neighbours exist to swipe to;
        // returns immediately when 圖鑑 already populated the store.
        .task { await self.wordsStore.loadIfNeeded() }
    }
}

/// A single word's detail screen. Owns its own load so each page in the
/// pager fetches and renders independently; the DETAILS / EXAMPLE sections
/// (and their tab state) live in the reusable WordDetailSections.
struct WordDetailPage: View {
    let id: String

    @Environment(\.dismiss) private var dismiss
    @Environment(MasteryStore.self) private var mastery
    @Environment(WordsStore.self) private var wordsStore
    @Environment(SettingsStore.self) private var settings

    @State private var word: Word?
    @State private var loading = false
    @State private var error: Error?
    private let repository: CatalogRepository = LiveCatalogRepository.shared

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if let word {
                    self.content(word, width: geo.size.width)
                } else if let error {
                    self.errorState(error)
                        .frame(width: geo.size.width)
                } else {
                    TujiImagePlaceholder()
                        .tint(.tujiCurrent)
                        .padding(.top, Space.s6)
                        .frame(width: geo.size.width)
                }
            }
        }
        .task {
            await self.load()
            await self.mastery.loadIfNeeded()
        }
    }

    // MARK: - States

    private func content(_ w: Word, width: CGFloat) -> some View {
        // This is a picture dictionary, so the picture is the first event on
        // the page — full-bleed, not an attachment inside a card. That means no
        // shared horizontal padding; every other section carries its own.
        VStack(alignment: .leading, spacing: Space.s4) {
            self.hero(w)
            self.titleRow(w).padding(.horizontal, Space.s4)
            MasteryBar(
                score: self.mastery.score(for: w.id),
                nextReview: self.mastery.nextReviewDate(for: w.id)
            )
            .padding(.horizontal, Space.s4)
            WordDetailSections(word: w).padding(.horizontal, Space.s4)
            WordCommunityAtlasSection(word: w).padding(.horizontal, Space.s4)
        }
        .padding(.bottom, Space.s6)
        .frame(width: width, alignment: .leading)
    }
}

extension WordDetailPage {
    private func errorState(_ err: Error) -> some View {
        VStack {
            Spacer(minLength: Space.s5)
            TujiErrorState(
                title: "找不到這個字",
                message: err.localizedDescription
            ) {
                BBtn(title: "返回", fullWidth: false, action: { self.dismiss() })
            }
            Spacer(minLength: Space.s5)
        }
        .padding(.horizontal, Space.s4)
    }

    // MARK: - Sections

    /// Whether this word's picture is dictionary artwork (a cut-out that should
    /// blend into the paper) or a photograph the user took.
    private func isCutout(_ w: Word) -> Bool {
        WordImageKind(category: w.category) == .cutout
    }

    private func hero(_ w: Word) -> some View {
        Color.tujiPaper2
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                LazyImage(url: w.imageURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: self.isCutout(w) ? .fit : .fill)
                            .padding(self.isCutout(w) ? Space.s5 : 0)
                            .blendMode(self.isCutout(w) ? .multiply : .normal)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tujiInk3)
                    } else {
                        TujiImagePlaceholder()
                    }
                }
                .pipeline(.shared)
            }
            .clipped()
            // Controls float over the artwork rather than taking a row of their
            // own. The bar is transparent, so the page starts with the picture.
            .overlay(alignment: .top) {
                HStack {
                    self.barControl(systemImage: "arrow.left", label: "返回") { self.dismiss() }
                    Spacer()
                    if !w.id.hasPrefix("atlas:") {
                        FavoriteButton(wordId: w.id)
                    }
                }
                .padding(.horizontal, Space.s4)
                .frame(height: 56)
            }
    }

    private func titleRow(_ w: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(w.word)
                    .font(.tujiDisplay)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Space.s2) {
                    if let pron = w.pronunciation {
                        Text(pron)
                            .font(.tujiMono)
                            .foregroundStyle(.tujiInk2)
                    }
                    if let pos = w.partOfSpeech, !pos.isEmpty {
                        Text(localizedPartOfSpeech(pos, language: self.settings.current.uiLanguage))
                            .font(.tujiLabel)
                            .italic()
                            .foregroundStyle(.tujiInk3)
                    }
                    if let cefr = w.cefrLevel {
                        Text(cefr)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk2)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(.tujiPaper2, in: .rect(cornerRadius: Radius.r0))
                    }
                }
            }
            Spacer()
            PronunciationButton(
                text: w.word,
                language: w.wordLanguage,
                audioUrls: w.audioUrls,
                size: 48,
                wordId: self.id.hasPrefix("atlas:") ? nil : w.id
            )
        }
    }

    private func barControl(
        systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(width: 48, height: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Load

    private func load() async {
        guard self.word == nil, !self.loading else { return }
        self.loading = true
        defer { self.loading = false }
        if self.id.hasPrefix("atlas:") {
            // /api/users/custom-words now embeds the full detail (definition /
            // synonyms / forms / etymology) enriched at capture time, so the
            // common path renders with zero extra round-trips.
            if let lite = self.wordsStore.find(id: self.id) {
                if let full = lite.detail {
                    self.word = full
                    return
                }
                // No embedded detail (cold store, or an item that missed
                // enrichment): show the lite card instantly, then upgrade via
                // the detail endpoint, which lazily enriches on first open.
                self.word = Self.provisionalWord(from: lite, tags: ["custom"])
            }
            do {
                let uuid = String(self.id.dropFirst("atlas:".count))
                self.word = try await AtlasStore.shared.detail(itemId: uuid)
            } catch {
                if self.word == nil { self.error = error }
            }
            return
        }
        // Public words: the grid already knows the word / image / 中文, so
        // render those instantly and let the enrichment sections (definitions,
        // 例句, 詞形, 來源) fill in when the full payload lands — a blank page
        // with a lone spinner made every card feel broken for 2-3s.
        if let lite = self.wordsStore.find(id: self.id) {
            self.word = Self.provisionalWord(from: lite, tags: [])
        }
        do {
            let settings = SettingsStore.shared.current
            self.word = try await self.repository.word(
                id: self.id,
                lang: settings.uiLanguage.contentLanguageCode,
                learning: settings.learningDirection.rawValue
            )
        } catch {
            if self.word == nil { self.error = error }
        }
        // Public-word page view (the atlas branch above returned already —
        // private 自製 content stays out of analytics).
        if let w = self.word {
            AnalyticsService.shared.track(.view, wordId: w.id, category: w.category)
        }
    }

    /// Lite grid payload → renderable Word shell: enough for the hero, title
    /// row, and 中文 definition while the full detail is fetched.
    private static func provisionalWord(from lite: CardWord, tags: [String]) -> Word {
        Word(
            id: lite.id,
            word: lite.word,
            alsoKnownAs: nil,
            category: lite.category,
            partOfSpeech: nil,
            pronunciation: lite.pronunciation,
            reading: lite.reading,
            targetLanguage: lite.targetLanguage,
            audioUrl: nil,
            audioUrls: lite.audioUrls,
            imageUrl: lite.imageUrl,
            cefrLevel: nil,
            status: "published",
            chinese: lite.chinese,
            definitions: [
                WordDefinition(language: "zh", definition: lite.chinese, cefrLevel: nil, sortOrder: 0)
            ],
            examples: nil,
            relations: nil,
            collocations: nil,
            collocationsZh: nil,
            note: nil,
            etymology: nil,
            forms: nil,
            chineseDefinition: lite.chinese,
            targetDefinition: nil,
            englishDefinition: nil,
            tags: tags
        )
    }
}

#Preview {
    NavigationStack {
        WordDetailView(id: "tomato")
            .environment(LocalCache.shared)
            .environment(AuthService.shared)
            .environment(StudyFocus.shared)
            .environment(WordsStore.shared)
            .environment(SettingsStore.shared)
            .environment(MasteryStore.shared)
    }
}

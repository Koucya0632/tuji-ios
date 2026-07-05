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
        .background(.tujiBg)
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
                    ProgressView()
                        .tint(.tujiTeal)
                        .padding(.top, Space.s16)
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
        VStack(alignment: .leading, spacing: Space.s5) {
            self.hero(w)
            self.titleRow(w)
            WordDetailSections(word: w)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s8)
        .frame(width: width, alignment: .leading)
    }
}

extension WordDetailPage {
    private func errorState(_ err: Error) -> some View {
        VStack {
            Spacer(minLength: Space.s12)
            MascotEmptyState(
                pose: .think,
                title: "找不到這個字",
                message: "\(err.localizedDescription)"
            ) {
                BBtn(title: "返回", fullWidth: false, action: { self.dismiss() })
            }
            Spacer(minLength: Space.s12)
        }
        .padding(.horizontal, Space.s6)
    }

    // MARK: - Sections

    /// Fixed image-card height so every word — wide, tall, square — gets an
    /// identically sized hero. The image always fits inside (never cropped),
    /// so layout stays neat and consistent across the dictionary.
    private static let imageCardHeight: CGFloat = 220

    private func hero(_ w: Word) -> some View {
        VStack(spacing: Space.s4) {
            // Controls live in their own row above the image so the back
            // button and favourite toggle are always fully visible, never
            // clipped by the notch or overlapping the artwork.
            HStack {
                self.circleControl(systemImage: "chevron.left") { self.dismiss() }
                Spacer()
                if !w.id.hasPrefix("atlas:") {
                    FavoriteButton(wordId: w.id)
                }
            }

            // Mastery + level badge sit above the artwork here, in full colour
            // (unlike the de-emphasized grey 圖鑑 tile badge).
            MasteryBar(score: self.mastery.score(for: w.id))

            // Consistent white image card. The picture is shown .fit with
            // padding, so the whole subject is visible regardless of its
            // aspect ratio or baked-in background.
            ZStack {
                RoundedRectangle(cornerRadius: Radius.xl)
                    .fill(.tujiBg)
                LazyImage(url: w.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                            .padding(Space.s4)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.imageCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(.tujiInk4.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private func titleRow(_ w: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(w.word)
                    .font(.tujiH1)
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
                        Text(pos)
                            .font(.tujiCaption)
                            .italic()
                            .foregroundStyle(.tujiInk3)
                    }
                    if let cefr = w.cefrLevel {
                        Text(cefr)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tujiTeal)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(.tujiTealSoft, in: .capsule)
                    }
                }
            }
            Spacer()
            PronunciationButton(text: w.word, audioUrls: w.audioUrls, size: 48)
        }
    }

    private func circleControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.tujiCard)
                    .overlay(Circle().stroke(.tujiInk4.opacity(0.3), lineWidth: 1.5))
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
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
                lang: settings.uiLang,
                learning: settings.learningDirection.rawValue
            )
        } catch {
            if self.word == nil { self.error = error }
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

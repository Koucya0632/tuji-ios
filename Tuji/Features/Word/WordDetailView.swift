// Per-word detail page (§III.H).
//
// Loads the full Word from GET /api/words/{id} the first time it appears.
// Sections render conditionally — etymology / examples / forms /
// collocations may all be empty for some words.

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
        // Hosts the 詞塊 card for every page's examples. On the pager rather
        // than on each page, so the screen has exactly one card — and the
        // scrim covers the pager, which is what stops a swipe from carrying an
        // open card to a different word.
        .glossCard()
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

    @State private var vm = WordDetailVM()

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if let word = self.vm.word {
                    self.content(word, width: geo.size.width)
                } else if let error = self.vm.error {
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

    private func hero(_ w: Word) -> some View {
        Color.tujiPaper2
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                // The ninth copy of the picture rules used to live here, behind
                // an `isCutout(_:)` helper — which is also why a search for the
                // other eight did not find it. It filled photographs to the
                // square, so the one screen devoted to a single word showed less
                // of it than the grid you tapped to get here.
                WordPicture(url: w.imageURL, kind: w.imageKind, inset: Space.s5, glyphSize: 28)
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
                // Size, wrapping and the reading line are the headword's own
                // decisions — see `TujiHeadword`. This screen only says where
                // the line goes: in the row, before the part of speech.
                TujiHeadword(word: w)
                HStack(spacing: Space.s2) {
                    TujiReadingLine(word: w)
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
            // An HStack splits its spare width evenly between equally-flexible
            // children, so with a `Spacer` alongside the headword is offered
            // half the row — which for a ruby word means picking a smaller size
            // than the column actually calls for. `Text` alone never showed
            // this, because it negotiates an ideal width of its own.
            .layoutPriority(1)
            Spacer()
            PronunciationButton(
                text: w.word,
                language: w.taggedLanguage,
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
                .font(.tujiIcon(20, weight: .semibold))
                .foregroundStyle(.tujiInk)
                .frame(width: 48, height: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Load

    /// Analytics stays in the View: the VM returns the word worth logging (nil
    /// for 自製圖鑑, which is private content and deliberately never counted).
    private func load() async {
        let current = self.settings.current
        let logged = await self.vm.load(
            id: self.id,
            lang: current.uiLanguage.contentLanguageCode,
            learning: current.learningDirection.rawValue
        )
        if let logged {
            AnalyticsService.shared.track(.view, wordId: logged.id, category: logged.category)
        }
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
            .environment(TabNavigator())
    }
}

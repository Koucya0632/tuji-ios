// WordPeek (§III.I).
//
// Lightweight bottom sheet for a quick word preview without leaving the
// current screen. .medium shows hero + word + favorite + audio and a CTA.
//
// Two modes:
// - Default (Cards / Favorites): CTA "看完整詳情" dismisses and pushes
//   WordDetailView (a swipeable pager). No inline detail.
// - Study wrong-answer (showDetailOnExpand: true): CTA is "下一題"; dragging
//   the sheet up to .large reveals the full WordDetailSections inline
//   (lazy-loaded), so the user can read the details without leaving the flow.

import Nuke
import NukeUI
import SwiftUI

struct WordPeekSheet: View {
    let word: CardWord
    let ctaTitle: LocalizedStringKey
    let showDetailOnExpand: Bool
    let onSeeMore: () -> Void

    @Environment(SettingsStore.self) private var settings

    @State private var detent: PresentationDetent

    /// Resting detent for the study sheet. There's no hero image and only a
    /// word + CTA at rest, so a short detent keeps the button close to the
    /// word; the user drags up to `.large` to reveal the full details.
    private static let studyRestDetent: PresentationDetent = .fraction(0.34)

    init(
        word: CardWord,
        ctaTitle: LocalizedStringKey = "看完整詳情",
        showDetailOnExpand: Bool = false,
        onSeeMore: @escaping () -> Void
    ) {
        self.word = word
        self.ctaTitle = ctaTitle
        self.showDetailOnExpand = showDetailOnExpand
        self.onSeeMore = onSeeMore
        _detent = State(initialValue: showDetailOnExpand ? Self.studyRestDetent : .medium)
    }

    private var restDetent: PresentationDetent {
        self.showDetailOnExpand ? Self.studyRestDetent : .medium
    }

    var body: some View {
        Group {
            if self.showDetailOnExpand {
                self.expandableBody
            } else {
                self.compactBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiBg)
        .presentationDetents([self.restDetent, .large], selection: self.$detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(.tujiBg)
        .presentationBackgroundInteraction(.enabled(upThrough: self.restDetent))
    }

    // MARK: - Layouts

    /// Cards / Favorites: hero + header, CTA pinned under a Spacer.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            self.heroImage
            self.headerRow
                .padding(.horizontal, Space.s6)
            Spacer(minLength: 0)
            self.ctaButton
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s5)
        }
        .padding(.top, Space.s2)
    }

    /// Study wrong-answer: scrollable hero + header, full details revealed
    /// when expanded to .large, with the CTA pinned to the bottom edge so
    /// "下一題" stays reachable at both detents.
    private var expandableBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                // No hero image here: the word's picture is already on screen
                // in the Identify / Spell question behind the sheet, so a
                // second copy would be redundant.
                self.headerRow
                    .padding(.horizontal, Space.s6)
                ExpandableWordDetail(wordId: self.word.id, expanded: self.detent == .large)
                    .padding(.horizontal, Space.s6)
                    .padding(.top, self.detent == .large ? 0 : Space.s6)
            }
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s4)
        }
        .safeAreaInset(edge: .bottom) {
            self.ctaButton
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s2)
                .padding(.bottom, Space.s5)
                .background(.tujiBg)
        }
    }

    private var ctaButton: some View {
        BBtn(
            title: self.ctaTitle,
            bg: .tujiTeal,
            fg: .white,
            fullWidth: true,
            icon: "arrow.right",
            action: self.onSeeMore
        )
    }

    // MARK: - Bits

    private var heroImage: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.tujiCard)
                LazyImage(url: self.word.imageURL) { state in
                    if let image = state.image {
                        image.resizable()
                            .scaledToFit()
                            .frame(
                                width: max(0, proxy.size.width - Space.s4),
                                height: max(0, proxy.size.height - Space.s4)
                            )
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.tujiInk4)
                    } else {
                        ProgressView().tint(.tujiTeal)
                    }
                }
                .pipeline(.shared)
            }
        }
        .frame(height: 188)
        .clipped()
        .clipShape(.rect(cornerRadius: Radius.lg))
        .padding(.horizontal, Space.s5)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(self.word.word)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if !self.word.pronunciation.isEmpty {
                    Text(self.word.pronunciation)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                if self.settings.current.showZh {
                    Text(self.word.chinese)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(spacing: Space.s2) {
                FavoriteButton(wordId: self.word.id, size: 44)
                PronunciationButton(text: self.word.word, audioUrls: self.word.audioUrls, size: 44)
            }
        }
    }
}

#Preview {
    Text("Tap to peek")
        .sheet(isPresented: .constant(true)) {
            WordPeekSheet(
                word: CardWord(
                    id: "tomato",
                    word: "tomato",
                    chinese: "番茄",
                    imageUrl: "",
                    category: "kitchen",
                    pronunciation: "/təˈmeɪtoʊ/"
                ),
                onSeeMore: {}
            )
        }
        .environment(LocalCache.shared)
        .environment(AuthService.shared)
        .environment(SettingsStore.shared)
}

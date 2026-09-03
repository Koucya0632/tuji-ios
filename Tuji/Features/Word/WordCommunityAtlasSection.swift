// 「大家的圖鑑」 — other users' public 圖鑑 photos for the word being viewed.
//
// This is the core of the community design (../docs/COMMUNITY_ATLAS_PLAN.md §1
// 原則 1 — FEATURES.md §8, §12): community content is injected into the page
// users already visit, rather than living in a separate feed nobody browses.
//
// Renders NOTHING when there is no content (or while loading). A word with no
// public photos must look exactly as it did before this section existed — no
// empty state, no placeholder, no layout shift.

import Nuke
import NukeUI
import SwiftUI

struct WordCommunityAtlasSection: View {
    let word: Word
    private let repo: PublicItemsReading

    @Environment(\.targetLanguage) private var language

    @State private var items: [AtlasPublicItem] = []
    @State private var loaded = false

    @Environment(BlockStore.self) private var blocks
    @Environment(TabNavigator.self) private var navigator

    init(word: Word, repo: PublicItemsReading = LiveAtlasRepository.shared) {
        self.word = word
        self.repo = repo
    }

    /// Everything below counts and renders this, never `items`. A word whose
    /// only public photos come from blocked authors has to look exactly like a
    /// word with no public photos at all — no heading, no count, no gap.
    private var visibleItems: [AtlasPublicItem] {
        self.items.filter { !self.blocks.isBlocked($0.author?.handle) }
    }

    var body: some View {
        Group {
            if self.loaded, !self.visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        Text("大家的圖鑑")
                            .font(.tujiBody(.strong))
                            .foregroundStyle(.tujiInk)
                        Text("\(self.visibleItems.count)")
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(Color.tujiBrandSecondary.opacity(0.1), in: .rect(cornerRadius: Radius.r0))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s3) {
                            ForEach(self.visibleItems) { item in
                                Button {
                                    self.navigator.push(.atlasPublicItem(item: item))
                                } label: {
                                    self.card(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: self.taskKey) {
            await self.load()
        }
    }

    /// Re-fetch when either the word or the learning direction changes.
    private var taskKey: String {
        "\(self.word.id)|\(self.language.rawValue)"
    }

    private func card(_ item: AtlasPublicItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(.tujiPaper)
                LazyImage(url: item.imageURL) { state in
                    if let image = state.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if state.error != nil {
                        Image(systemName: "photo")
                            .font(.tujiIcon(18))
                            .foregroundStyle(.tujiInk3)
                    } else {
                        TujiImagePlaceholder()
                    }
                }
                .pipeline(.shared)
            }
            .frame(width: 132, height: 100)
            .clipped()

            HStack(spacing: Space.s1) {
                if let author = item.author {
                    Text("by \(author.displayName)")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // No 收藏 marker here. There was one, and it could never fill:
                // it read a `savedSlugs` set that nothing in the repo ever
                // wrote to. The list endpoint is public and carries no per-user
                // saved flag, this section has no save action of its own, and
                // saving from the detail it pushes reports back through no
                // channel — `CollectionBookmarkStore` broadcasts 合集
                // bookmarks, not items. So the glyph promised a state it had no
                // way to reach, on a tile whose whole affordance is "tap to
                // open". Giving it a real one means an item-level broadcast,
                // which is a feature rather than a repair.
            }
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s2)
            .frame(width: 132, alignment: .leading)
        }
        .background(.tujiPaper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.25), lineWidth: 1)
        )
    }

    private func load() async {
        // The lemma is what the backend aggregates on; for dictionary words
        // that's the headword itself.
        let lemma = self.word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty else {
            self.loaded = true
            return
        }
        do {
            let items = try await self.repo.publicItems(
                lemma: lemma,
                language: self.language,
                limit: 12
            )
            self.items = items
        } catch {
            // Community content is additive: a failure hides the section rather
            // than surfacing an error on an otherwise fine word page.
            self.items = []
        }
        self.loaded = true
    }
}

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

    @Environment(SettingsStore.self) private var settings

    @State private var items: [AtlasPublicItem] = []
    @State private var loaded = false
    @State private var selected: AtlasPublicItem?
    /// Slugs saved during this session — the list endpoint is public and
    /// therefore can't carry a per-user saved flag.
    @State private var savedSlugs: Set<String> = []

    @Environment(BlockStore.self) private var blocks

    init(word: Word, repo: PublicItemsReading = LiveAtlasRepository.shared) {
        self.word = word
        self.repo = repo
    }

    private var language: TargetLanguage {
        self.settings.current.learningDirection.targetLanguage
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
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.tujiInk)
                        Text("\(self.visibleItems.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.tujiTeal)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(.tujiTealSoft, in: .rect(cornerRadius: Radius.r0))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.s3) {
                            ForEach(self.visibleItems) { item in
                                Button {
                                    self.selected = item
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
                .navigationDestination(item: self.$selected) { item in
                    AtlasPublicDetailView(item: item)
                }
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
                            .font(.system(size: 18))
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Saving here uses the consumption quota, not the user's 自製
                // 圖鑑 capacity (../docs/COMMUNITY_ATLAS_PLAN.md §4.1 —
                // FEATURES.md §12.1).
                Image(systemName: self.savedSlugs.contains(item.slug) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tujiTeal)
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

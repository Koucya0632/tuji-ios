// One 景點: how far through its words this account is, a way to study them,
// and the words themselves.
//
// The words are ordinary 官方圖鑑 words. Browsing them is never gated — a tile
// opens the word page for anyone. Studying follows the spot: a non-member may
// study a free spot and meets the paywall at any other.
//
// Below them, the 自製圖鑑 cards taken here: 「你在這裡拍的」 (this account's
// own tags, private) and 「大家拍的」 (public cards their owners shared to this
// spot). Each section is absent when it has nothing.

import SwiftUI

struct TravelSpotView: View {
    let spotId: String

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(MasteryStore.self) private var mastery
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(BlockStore.self) private var blocks
    @Environment(TabNavigator.self) private var navigator
    var store: TravelStore = .shared
    var atlas: AtlasStore = .shared
    /// 「大家拍的」 for a spot (`/api/travel/spots/{spot}/photos`).
    var loadSharedPhotos: @MainActor (String) async throws -> [AtlasPublicItem] = {
        try await LiveAtlasRepository.shared.spotPhotos(spotId: $0)
    }

    @State private var shared: [AtlasPublicItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s2, alignment: .top), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {}
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.content
                }
                .padding(.bottom, Space.s6)
            }
        }
        .background(.tujiPaper)
        .navigationTitle(Text(verbatim: self.store.spot(self.spotId)?.name ?? ""))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.store.loadIfNeeded(settings: self.settings)
            await self.words.loadIfNeeded()
            await self.mastery.loadIfNeeded()
        }
        .task(id: self.spotId) {
            // Own tags arrive with sync; 圖鑑 is not synced at launch.
            await self.atlas.sync()
            self.shared = await (try? self.loadSharedPhotos(self.spotId)) ?? self.shared
        }
    }

    @ViewBuilder
    private var content: some View {
        if let spot = self.store.spot(self.spotId) {
            let state = TravelDecisions.state(
                of: spot,
                words: self.words.words,
                scores: self.mastery.byId,
                nextReview: self.mastery.nextReviewById,
                studyable: LiveEffectiveEntitlement.shared.membership?.studyableCategories
            )
            self.hero(spot, state)
            Text("這裡會看到")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s2)
            LazyVGrid(columns: self.columns, spacing: Space.s3) {
                ForEach(state.words) { word in
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        WordTile(word: word, showMastery: true, masteryScore: self.mastery.score(for: word.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s4)
            self.ownSection(spot)
            self.sharedSection
        } else if self.store.phase == .failed {
            TujiBlankState(kind: .failed, retry: { await self.store.reload(settings: self.settings) })
        } else if self.store.phase == .loaded {
            TujiBlankState(kind: .empty("這裡還沒開"))
        } else {
            TujiPageLoading()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s6)
        }
    }

    // MARK: - 自製圖鑑 at this spot

    /// This account's own cards tagged here, as the custom words 圖鑑 shows.
    private func ownWords(_ spot: TravelSpot) -> [CardWord] {
        let itemIds = Set(self.atlas.items.filter { $0.spotId == spot.id }.map(\.id))
        guard !itemIds.isEmpty else { return [] }
        return self.words.words.filter { $0.id.atlasItemId.map(itemIds.contains) ?? false }
    }

    /// 「大家拍的」 without this account's own cards and authors it blocked —
    /// the server answers the same list to everyone.
    private var othersShared: [AtlasPublicItem] {
        let ownSlugs = Set(self.atlas.items.compactMap(\.publicSlug))
        return self.shared.filter { !ownSlugs.contains($0.slug) && !self.blocks.isBlocked($0.author?.handle) }
    }

    @ViewBuilder
    private func ownSection(_ spot: TravelSpot) -> some View {
        let own = self.ownWords(spot)
        if !own.isEmpty {
            self.sectionTitle("你在這裡拍的")
            LazyVGrid(columns: self.columns, spacing: Space.s3) {
                ForEach(own) { word in
                    NavigationLink(value: NavRoute.wordDetail(id: word.id)) {
                        WordTile(word: word, showMastery: true, masteryScore: self.mastery.score(for: word.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s4)
        }
    }

    @ViewBuilder
    private var sharedSection: some View {
        let others = self.othersShared
        if !others.isEmpty {
            self.sectionTitle("大家拍的")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2, alignment: .top), count: 2),
                spacing: Space.s3
            ) {
                ForEach(others) { item in
                    AtlasPublicTile(
                        item: item,
                        onOpen: { self.navigator.push(.atlasPublicItem(item: item)) },
                        onOpenAuthor: item.author.map { author in
                            { self.navigator.push(.authorProfile(handle: author.handle, isSelf: false)) }
                        }
                    )
                }
            }
            .padding(.horizontal, Space.s4)
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk3)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s2)
    }

    private func hero(_ spot: TravelSpot, _ state: TravelSpotState) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: spot.name)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiPaper)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: "\(spot.native) · \(spot.reading)")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiPaper3)
            }
            HStack(spacing: Space.s3) {
                TujiProgressBar(progress: state.progress, track: .tujiInk2, fill: .tujiAccumulationSoft)
                    .frame(height: 6)
                Text("\(state.studied) / \(state.total) 字")
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiPaper)
            }
            self.actions(spot, state)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
        .padding(.horizontal, Space.s4)
    }

    @ViewBuilder
    private func actions(_ spot: TravelSpot, _ state: TravelSpotState) -> some View {
        if state.access == .needsMembership {
            Button { self.presentPaywall() } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "lock.fill")
                        .font(.tujiIcon(13, weight: .semibold))
                    Text("學這裡的字需要永久會員")
                        .font(.tujiBodySm(.strong))
                }
                .foregroundStyle(.tujiInk)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.tujiBrandPrimary)
            }
            .buttonStyle(.plain)
        } else if state.studyModes.isEmpty {
            Text(state.total == 0 ? "字還在路上" : "這裡的字都學過了，到期會出現在複習")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiPaper3)
        } else {
            HStack(spacing: Space.s3) {
                ForEach(state.studyModes, id: \.self) { mode in
                    NavigationLink(value: TravelRoute.study(spotId: spot.id, mode: mode)) {
                        Text(mode == .new ? "學這裡的字" : "複習")
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(mode == .new ? Color.tujiBrandPrimary : .tujiPaper2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

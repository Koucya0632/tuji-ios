// One 景點: how far through its words this account is, a way to study them,
// and the words themselves.
//
// The words are ordinary 官方圖鑑 words. Browsing them is never gated — a tile
// opens the word page for anyone. Studying follows the spot: a non-member may
// study a free spot and meets the paywall at any other.

import SwiftUI

struct TravelSpotView: View {
    let spotId: String

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(MasteryStore.self) private var mastery
    @Environment(\.presentPaywall) private var presentPaywall
    var store: TravelStore = .shared

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

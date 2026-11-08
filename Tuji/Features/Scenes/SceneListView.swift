// 場面練習 — every 場面 as a card. A list, not a banner, because more 場面 are
// coming (場面練習方案 §3).

import SwiftUI

struct SceneListView: View {
    let user: SessionUser?
    var catalog: SceneCatalog = .bundled

    @Environment(SettingsStore.self) private var settings
    private let store = SceneProgressStore.shared

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            ScrollView {
                TujiScreenTitle("場面練習")
                LazyVStack(spacing: Space.s3) {
                    ForEach(self.catalog.scenes) { scene in
                        NavigationLink(value: NavRoute.sceneDetail(id: scene.id)) {
                            self.card(scene)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s6)
            }
        }
        .background(.tujiPaper)
        .navigationTitle("場面練習")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let user { self.store.use(account: user.id) }
        }
    }

    private func card(_ scene: PracticeScene) -> some View {
        let language = self.settings.current.uiLanguage
        let status = ScenePractice.status(scene, book: self.store.book, today: LocalDay(Date(), calendar: .current))
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text(verbatim: scene.title.resolved(language))
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text(verbatim: scene.summary.resolved(language))
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
            HStack(spacing: Space.s2) {
                Text("\(scene.questions.count) 個問句")
                Text(verbatim: "·")
                Text(status.label)
                    .foregroundStyle(status.isOwedToday ? .tujiInk : .tujiInk3)
            }
            .font(.tujiLabel)
            .foregroundStyle(.tujiInk3)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
        .contentShape(.rect)
    }
}

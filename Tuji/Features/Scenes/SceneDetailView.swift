// One 場面's page, which is also 進店前看一眼: every 問句 with its Japanese, what
// it means and the shortest 回應, each playable. It reads only bundled files, so
// it works offline and before any practice.

import SwiftUI

struct SceneDetailView: View {
    let sceneId: SceneID
    let user: SessionUser?
    var catalog: SceneCatalog = .bundled

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words
    @Environment(\.presentPaywall) private var presentPaywall
    private let store = SceneProgressStore.shared
    @State private var glossed: GlossToken?

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            if let scene = self.catalog.scene(self.sceneId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        self.header(scene)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("進店前看一眼")
                                .font(.tujiH3)
                                .foregroundStyle(.tujiInk)
                            Text("不用網路也能看、能播。")
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiInk2)
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.top, 32)
                        .padding(.bottom, 12)
                        Rectangle().fill(.tujiRule).frame(height: 1)
                        ForEach(Array(scene.questions.enumerated()), id: \.element.id) { index, question in
                            self.lookRow(question, number: index + 1, scene: scene)
                            Rectangle().fill(.tujiRule).frame(height: 1)
                        }
                    }
                    .padding(.bottom, Space.s5)
                }
            } else {
                Spacer()
            }
        }
        .background(.tujiPaper)
        .glossSheet(self.$glossed)
        .navigationTitle("場面練習")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let user { self.store.use(account: user.id) }
        }
        .onDisappear { SpeechService.shared.stop() }
    }

    private var language: UILanguage {
        self.settings.current.uiLanguage
    }

    // MARK: - Header

    private func header(_ scene: PracticeScene) -> some View {
        let today = LocalDay(Date(), calendar: .current)
        let status = ScenePractice.status(scene, book: self.store.book, today: today)
        let practised = scene.practised(in: self.store.book)
        let canPractise = scene.canPractise(LiveEffectiveEntitlement.shared.tier)
        return VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                Text("場面練習")
                    .font(.tujiLabel)
                    .tracking(1)
                    .foregroundStyle(.tujiPaper.opacity(0.7))
                Text(verbatim: scene.title.resolved(self.language))
                    .font(.tujiH2)
                    .foregroundStyle(.tujiPaper)
                Text(verbatim: scene.summary.resolved(self.language))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiPaper.opacity(0.85))
                    .padding(.top, 2)
            }
            if status != .notStarted {
                HStack(spacing: Space.s3) {
                    SceneSegments(practised: practised, onInk: true)
                    Text(verbatim: "\(practised.count(where: \.self)) / \(practised.count)")
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiAccumulationSoft)
                }
            }
            if self.user != nil {
                if canPractise {
                    NavigationLink(value: NavRoute.scenePractice(id: scene.id, route: nil)) {
                        self.callLabel(status.startTitle, trailing: self.callTrailing(scene, status: status))
                    }
                    .buttonStyle(.plain)
                    ForEach(scene.stage?.routes.filter(\.isOptional) ?? []) { route in
                        NavigationLink(value: NavRoute.scenePractice(id: scene.id, route: route.id)) {
                            HStack(spacing: Space.s2) {
                                Text("另一趟：\(route.title.resolved(self.language))")
                                    .font(.tujiBodySm(.strong))
                                Spacer(minLength: Space.s2)
                                Image(systemName: "chevron.right").font(.tujiIcon(13, weight: .bold))
                            }
                            .foregroundStyle(.tujiPaper)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button { self.presentPaywall() } label: {
                        self.callLabel("看永久會員方案", trailing: nil)
                    }
                    .buttonStyle(.plain)
                    Text("練習這個場面需要永久會員。看一眼不用。")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiPaper.opacity(0.7))
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiInk)
        .padding(.top, Space.s2)
    }

    private func callTrailing(_ scene: PracticeScene, status: SceneStatus) -> LocalizedStringKey? {
        switch status {
        case .inProgress:
            "第 \(scene.resumeNumber(in: self.store.book)) 句"
        case let .reviewDue(count):
            "\(count) 句"
        case .notStarted:
            "約 \(scene.minutes) 分鐘"
        case .reviewLater, .complete:
            nil
        }
    }

    private func callLabel(_ title: LocalizedStringKey, trailing: LocalizedStringKey?) -> some View {
        HStack {
            Text(title).font(.tujiH3)
            Spacer(minLength: Space.s2)
            if let trailing {
                Text(trailing).font(.tujiBodySm(.strong)).opacity(0.75)
            }
        }
        .foregroundStyle(.tujiInk)
        .padding(.vertical, Space.s3)
        .padding(.horizontal, 20)
        .background(.tujiCurrent)
        .contentShape(.rect)
    }

    // MARK: - 進店前看一眼

    private func lookRow(_ question: SceneQuestion, number: Int, scene: PracticeScene) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .frame(width: 16, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    SceneSpeakerTag(speaker: question.lookSpeaker)
                    if let meaning = question.meaning {
                        Text(verbatim: meaning.resolved(self.language))
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiInk2)
                    }
                }
                if let line = question.lookLine {
                    HStack(spacing: Space.s2) {
                        GlossedLine(text: line.text, tokens: scene.gloss(line.text), picked: self.$glossed)
                            .font(.tujiH3)
                            .foregroundStyle(.tujiInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ScenePlayButton(label: "播放") { SceneAudio.play(line) }
                    }
                } else if let screen = question.firstPhrasing?.screen {
                    ScreenMockThumbnail(screen: screen, correctId: question.correctChoice?.id)
                        .padding(.vertical, 6)
                }
                HStack(spacing: Space.s2) {
                    Text("回應")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                        .frame(width: 28, alignment: .leading)
                    GlossedLine(
                        text: question.response.ja,
                        tokens: scene.gloss(question.response.ja),
                        picked: self.$glossed
                    )
                    .font(.scene(15))
                    .foregroundStyle(.tujiInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if question.response.clip != nil {
                        ScenePlayButton(label: "播放回應", fill: nil) { SceneAudio.play(question.response) }
                    }
                }
                .frame(minHeight: 44)
                .padding(.top, 6)
                if question.kind == .screen {
                    Text("畫面依店家不同")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                }
                let words = question.relatedWords(in: self.words, direction: self.settings.current.learningDirection)
                if !words.isEmpty {
                    SceneWordList(words: words, opening: .push(from: scene.id))
                        .padding(.top, Space.s2)
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.leading, Space.s4)
        .padding(.trailing, 12)
    }
}

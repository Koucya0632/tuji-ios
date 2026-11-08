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
    private let store = SceneProgressStore.shared

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            if let scene = self.catalog.scene(self.sceneId) {
                self.content(scene)
            } else {
                Spacer()
            }
        }
        .background(.tujiPaper)
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

    private func content(_ scene: PracticeScene) -> some View {
        let status = ScenePractice.status(scene, book: self.store.book, today: LocalDay(Date(), calendar: .current))
        return ScrollView {
            TujiScreenTitle(localized: scene.title.resolved(self.language))
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(verbatim: scene.summary.resolved(self.language))
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                if self.user != nil {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        NavigationLink(value: NavRoute.scenePractice(id: scene.id)) {
                            Text(status.startTitle)
                                .font(.tujiBody(.strong))
                                .foregroundStyle(.tujiInk)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(.tujiBrandPrimary)
                        }
                        .buttonStyle(.plain)
                        Text(status.label)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                    }
                }
                Text("進店前看一眼")
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
                    .padding(.top, Space.s2)
                VStack(spacing: 0) {
                    ForEach(scene.questions) { question in
                        self.lookRow(question)
                        Rectangle().fill(.tujiRule).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s6)
        }
    }

    private func lookRow(_ question: SceneQuestion) -> some View {
        let line = question.lookLine
        let meaning = question.kind == .listening ? question.correctChoice?.text : question.goal
        let entry = HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                if let line {
                    Text(verbatim: line.text)
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                }
                if question.kind == .screen, let screen = question.firstPhrasing?.screen {
                    Label {
                        Text(verbatim: screen.heading)
                    } icon: {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                    }
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                }
                if let meaning {
                    Text(verbatim: meaning.resolved(self.language))
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
                HStack(spacing: Space.s2) {
                    Text("回應")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk3)
                    Text(verbatim: question.response.ja)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                }
                .padding(.top, Space.s1)
            }
            Spacer(minLength: 0)
            if let line {
                ScenePlayButton(label: "播放") { SceneAudio.play(line) }
            }
        }
        return VStack(alignment: .leading, spacing: Space.s3) {
            entry
            let words = question.relatedWords(in: self.words, direction: self.settings.current.learningDirection)
            if !words.isEmpty {
                SceneWordList(words: words, opening: .push)
            }
        }
        .padding(.vertical, Space.s3)
    }
}

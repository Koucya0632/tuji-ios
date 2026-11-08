// The ways into 場面練習 from elsewhere: 今天's card beside Moira, a topic
// page's row under 用這個主題聊聊, and a word page's 場面 section. Scenes
// reference the Japanese 圖鑑 only, so all three show for zh-ja learners alone.

import SwiftUI

extension LearningDirection {
    var hasScenes: Bool {
        self == .zhJa
    }
}

/// 今天's card: one scene, its signature line in large type, and where it
/// stands. `SceneCards.pick` chooses the scene.
struct SceneTodayCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AuthService.self) private var auth
    private let store = SceneProgressStore.shared

    var body: some View {
        let today = LocalDay(Date(), calendar: .current)
        let tier = LiveEffectiveEntitlement.shared.tier
        if let pick = SceneCards.pick(
            SceneCatalog.bundled.scenes,
            book: self.store.book,
            today: today,
            canPractise: { $0.canPractise(tier) }
        ) {
            self.card(pick)
                .task(id: self.auth.session.signedInUser?.id) {
                    if let id = self.auth.session.signedInUser?.id { self.store.use(account: id) }
                }
        }
    }

    private func card(_ pick: SceneCardPick) -> some View {
        let language = self.settings.current.uiLanguage
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("場面練習")
                    .font(.tujiLabel)
                    .tracking(1)
                    .foregroundStyle(.tujiInk2)
                Spacer()
                NavigationLink(value: NavRoute.sceneList) {
                    HStack(spacing: 2) {
                        Text("全部")
                        Image(systemName: "chevron.right").font(.tujiIcon(12, weight: .bold))
                    }
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk2)
                    .padding(.leading, Space.s3)
                    .padding(.trailing, 10)
                    .frame(height: 40)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, Space.s3)
            NavigationLink(value: NavRoute.sceneDetail(id: pick.scene.id)) {
                VStack(alignment: .leading, spacing: 0) {
                    if let line = pick.scene.questions.first?.lookLine {
                        Text(verbatim: "「\(line.text)」")
                            .font(.scene(20))
                            .foregroundStyle(.tujiInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(verbatim: pick.scene.title.resolved(language))
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk2)
                        .lineLimit(1)
                        .padding(.top, 2)
                    Spacer(minLength: Space.s2)
                    SceneSegments(practised: pick.state == .notStarted ? pick.practised.map { _ in
                        false
                    } : pick.practised)
                    HStack(spacing: 6) {
                        self.status(pick)
                        Spacer(minLength: Space.s1)
                        HStack(spacing: 2) {
                            Text(self.verb(pick.state))
                            Image(systemName: "chevron.right").font(.tujiIcon(12, weight: .bold))
                        }
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, 2)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 198)
        .background(.tujiPaper)
        .overlay(Rectangle().strokeBorder(.tujiRule, lineWidth: 1))
        .accessibilityIdentifier("today-scene-card")
    }

    @ViewBuilder
    private func status(_ pick: SceneCardPick) -> some View {
        switch pick.state {
        case .notStarted:
            Text("\(pick.scene.questions.count) 句 · 約 \(pick.scene.minutes) 分鐘")
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk2)
        case let .inProgress(at):
            Text("練到第 \(at) 句")
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk2)
        case .reviewDue:
            HStack(spacing: 6) {
                Rectangle().fill(.tujiCurrent).frame(width: 8, height: 8)
                Text("今天複習").font(.tujiLabel).foregroundStyle(.tujiInk)
            }
        case let .allDone(status):
            Text(status == .complete ? "複習完了" : "明天複習")
                .font(.scene(13, bold: false))
                .foregroundStyle(.tujiInk2)
        }
    }

    private func verb(_ state: SceneCardPick.State) -> LocalizedStringKey {
        switch state {
        case .notStarted: "開始"
        case .inProgress: "繼續"
        case .reviewDue: "複習"
        case .allDone: "看一眼"
        }
    }
}

/// A topic page's way into the scenes that use its words, at most two.
struct SceneTopicEntries: View {
    let topic: String

    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words

    var body: some View {
        if self.settings.current.learningDirection.hasScenes {
            let topicOf = Dictionary(
                self.words.words.map { ($0.id, $0.category) },
                uniquingKeysWith: { first, _ in first }
            )
            let scenes = SceneLinks.scenes(forTopic: self.topic, topicOf: topicOf, in: .bundled)
            ForEach(scenes) { scene in
                NavigationLink(value: NavRoute.sceneDetail(id: scene.id)) {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.tujiIcon(16, weight: .semibold))
                            .foregroundStyle(.tujiPaper)
                            .frame(width: 36, height: 36)
                            .background(.tujiInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("場面練習：\(scene.title.resolved(self.settings.current.uiLanguage))")
                                .font(.tujiBody(.strong))
                                .foregroundStyle(.tujiInk)
                            Text(verbatim: scene.summary.resolved(self.settings.current.uiLanguage))
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                                .lineLimit(2)
                        }
                        Spacer(minLength: Space.s2)
                        TujiRowAccessory()
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .frame(minHeight: 56)
                    .background(.tujiPaper2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("category-scene-\(scene.id.rawValue)")
            }
        }
    }
}

/// 場面 · SCENE on a word page: the 問句 that ask about this word, grouped by
/// scene, each playable, with a row into the scene.
struct WordSceneSection: View {
    let wordId: String
    let excluding: SceneID?

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let mentions = self.settings.current.learningDirection.hasScenes
            ? SceneLinks.mentions(of: self.wordId, in: .bundled, excluding: self.excluding)
            : []
        if !mentions.isEmpty {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("場面 · SCENE")
                    .font(.tujiLabel)
                    .tracking(2)
                    .foregroundStyle(.tujiInk3)
                    .padding(.top, Space.s4)
                ForEach(mentions) { mention in
                    self.box(mention)
                }
            }
        }
    }

    private func box(_ mention: SceneMention) -> some View {
        let language = self.settings.current.uiLanguage
        return VStack(spacing: 0) {
            ForEach(mention.questions) { question in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        SceneSpeakerTag(speaker: question.lookSpeaker)
                        if let line = question.lookLine {
                            Text(verbatim: line.text)
                                .font(.scene(17))
                                .foregroundStyle(.tujiInk)
                        }
                        if let meaning = question.meaning {
                            Text(verbatim: meaning.resolved(language))
                                .font(.tujiBodySm(.strong))
                                .foregroundStyle(.tujiInk3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let line = question.lookLine {
                        ScenePlayButton(label: "播放") { SceneAudio.play(line) }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, Space.s3)
                .padding(.leading, 18)
                .padding(.trailing, 12)
                Rectangle().fill(.tujiRule).frame(height: 1)
            }
            NavigationLink(value: NavRoute.sceneDetail(id: mention.scene.id)) {
                HStack(spacing: Space.s2) {
                    Text(verbatim: mention.scene.title.resolved(language))
                        .font(.scene(15))
                        .foregroundStyle(.tujiInk)
                    Spacer(minLength: Space.s2)
                    Text("\(mention.scene.questions.count) 句")
                        .font(.scene(13, bold: false))
                        .foregroundStyle(.tujiInk2)
                    TujiRowAccessory()
                }
                .padding(.leading, 18)
                .padding(.trailing, Space.s3)
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .overlay(Rectangle().strokeBorder(.tujiRule, lineWidth: 1))
    }
}

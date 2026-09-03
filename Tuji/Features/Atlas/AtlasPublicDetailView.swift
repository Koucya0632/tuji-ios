// 物見的項目詳情頁 —— 一張別人公開的照片，以及讀者能對它做的三件事：
// 收進圖鑑、檢舉、封鎖作者。
//
// 它住在 `AtlasPublicFeedView.swift` 裡，因為列表是它唯一的入口。那個檔案因此有
// 740 行、四個頂層型別，其中一個是整個畫面——而下一個要找「物見詳情」的人，會照著
// 名字去找一個不存在的檔案。**module 不該用它唯一的呼叫者命名**，畫面也一樣。
//
// `AtlasSavedItemDetailView` 走的也是這裡。

import Nuke
import NukeUI
import SwiftUI

// MARK: - 詳情頁

struct AtlasPublicDetailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(MasteryStore.self) private var mastery
    @Environment(TabNavigator.self) private var navigator
    @Environment(SettingsStore.self) private var settings
    @Environment(BlockStore.self) private var blocks
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AtlasPublicDetailVM
    @State private var report = ReportFlow()
    @State private var showBlockPrompt = false
    @State private var showStopLearningPrompt = false
    // The author route is keyed by handle, never by display name — two people
    // may share a name, and only the handle is a valid path component.

    init(
        item: AtlasPublicItem,
        repo: AtlasItemConsuming = LiveAtlasRepository.shared,
        itemReader: PublicItemsReading = LiveAtlasRepository.shared
    ) {
        _vm = State(initialValue: AtlasPublicDetailVM(
            item: item,
            repo: repo,
            itemReader: itemReader
        ))
    }

    /// What the viewer is to this item. One answer for both the moderation
    /// controls and the 「你的分享」 pill, which used to be two computed
    /// properties three hundred lines apart with different guards — the pill's
    /// asked `owns` alone.
    private var relationship: ViewerRelationship? {
        self.auth.relationship(toAuthor: self.vm.item.author?.handle)
    }

    /// Blocking is keyed by the immutable TJ-UID, so an item whose author never
    /// resolved simply offers no block action rather than a broken one — and an
    /// item of your own offers none either, since blocking yourself would hide
    /// your own 圖鑑 from you.
    private var authorHandle: String? {
        guard self.relationship == .theirs else { return nil }
        return self.vm.item.author?.handle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if self.vm.saved {
                    MasteryBar(score: self.mastery.score(for: "saved:\(self.vm.item.slug)"))
                }

                self.imageCard

                if let word = self.vm.item.learningWord {
                    self.titleRow(word)
                } else {
                    self.previewTitle
                }

                self.socialLearningRow

                if let word = self.vm.item.learningWord {
                    WordDetailSections(word: word)
                }

                if let actionError = self.vm.actionError {
                    Text(actionError)
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiAlert)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    self.report.begin(.item(slug: self.vm.item.slug))
                } label: {
                    Text(self.report.isSent ? "已收到檢舉" : "檢舉這個項目")
                        .font(.tujiLabel)
                        .foregroundStyle(self.report.isSent ? .tujiInk3 : .tujiAlert)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                }
                .buttonStyle(.plain)
                .disabled(self.report.isSent)

                // 檢舉 asks someone else to judge this one item; 封鎖 is the
                // reader's own decision about everything by this author. They
                // answer different needs, so they sit together.
                if let handle = self.authorHandle {
                    // `BlockAction`'s copy, not a third spelling of it. This
                    // screen used to write its own 「已封鎖這位作者」 — a string
                    // that exists nowhere in the module — and disable the
                    // button, so a reader who had blocked someone could undo it
                    // on 作者主頁 and nowhere else. The module's own header
                    // names this exact drift; only one of its two callers had
                    // been moved.
                    let block = BlockAction(isBlocked: self.blocks.isBlocked(handle))
                    Button {
                        self.showBlockPrompt = true
                    } label: {
                        Text(block.controlLabel)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.s4)
        }
        .background(.tujiPaper)
        // Hosts the 詞塊 card for the example sentences `WordDetailSections`
        // renders above. They were never inert data: when a capture's lemma is
        // also a catalogue word the public-item route hands back that word's
        // annotated examples, so this page has had tappable 詞塊 all along and
        // no one to deliver the tap to — which reads as the feature being
        // broken rather than absent. `AtlasSavedItemDetailView` reaches the
        // same screen, so both routes are covered by this one line.
        .glossCard()
        .navigationTitle(self.vm.item.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            AnalyticsService.shared.track(.atlasPublicItemViewed)
            async let detail: Void = self.vm.loadDetail()
            async let saveState: Void = self.vm.loadSaveState()
            async let mastery: Void = self.mastery.loadIfNeeded()
            _ = await (detail, saveState, mastery)
        }
        .tujiPrompt(
            isPresented: self.$showStopLearningPrompt,
            style: .confirmation,
            title: "停止學習這個單詞？",
            primary: TujiPromptAction("確定", role: .destructive) {
                Task { _ = await self.vm.toggleSave() }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
        .blockPrompt(
            handle: self.authorHandle,
            isPresented: self.$showBlockPrompt,
            onBlocked: { self.dismiss() }
        )
        .reportSheet(self.report)
    }

    private var imageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.r0)
                .fill(.tujiPaper)
            LazyImage(url: self.vm.item.imageURL) { state in
                if let image = state.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Space.s3)
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.tujiIcon(28))
                        .foregroundStyle(.tujiInk3)
                } else {
                    TujiImagePlaceholder()
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.2), lineWidth: 1)
        )
    }

    private var previewTitle: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(self.vm.item.lemma)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                Text(self.vm.item.langBadge)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiBrandSecondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 3)
                    .background(Color.tujiBrandSecondary.opacity(0.1), in: .rect(cornerRadius: Radius.r0))
            }
            Text(self.vm.item.displayZhHant)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
        }
    }

    private func titleRow(_ word: Word) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s2) {
                TujiHeadword(word: word)
                HStack(spacing: Space.s2) {
                    TujiReadingLine(word: word)
                    if let partOfSpeech = word.partOfSpeech, !partOfSpeech.isEmpty {
                        Text(localizedPartOfSpeech(
                            partOfSpeech,
                            language: self.settings.current.uiLanguage
                        ))
                        .font(.tujiLabel)
                        .italic()
                        .foregroundStyle(.tujiInk3)
                    }
                    if let cefr = word.cefrLevel, !cefr.isEmpty {
                        Text(cefr)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 2)
                            .background(Color.tujiBrandSecondary.opacity(0.1), in: .rect(cornerRadius: Radius.r0))
                    }
                }
            }
            // See WordDetailView.titleRow: beside a `Spacer` the headword is
            // offered half the row unless it is prioritised.
            .layoutPriority(1)
            Spacer()
            PronunciationButton(
                subject: .headword(
                    word.word,
                    language: word.taggedLanguage,
                    clips: word.audioUrls
                ),
                size: 48
            )
        }
    }

    private var socialLearningRow: some View {
        HStack(spacing: Space.s2) {
            if let author = self.vm.item.author {
                Button {
                    self.navigator.push(.authorProfile(handle: author.handle, isSelf: false))
                } label: {
                    HStack(spacing: 6) {
                        ProfileAvatar(avatar: author.avatar, size: 24)
                        Text(author.displayName)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiBrandSecondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }

            Text("\(self.vm.saveCount ?? 0) 人學習中")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .lineLimit(1)

            Spacer(minLength: Space.s2)

            if self.isOwnItem {
                self.learningPillLabel(icon: nil, title: "你的分享", active: true)
            } else {
                Button {
                    if self.vm.saved {
                        self.showStopLearningPrompt = true
                    } else {
                        Task {
                            if await self.vm.toggleSave() == true {
                                AnalyticsService.shared.track(.atlasPublicSaved)
                            }
                        }
                    }
                } label: {
                    self.learningPillLabel(
                        icon: self.vm.saved ? "checkmark" : "plus",
                        title: self.vm.saved ? "學習中" : "加入學習",
                        active: self.vm.saved
                    )
                }
                .buttonStyle(.plain)
                .disabled(self.vm.busy)
                .opacity(self.vm.busy ? 0.6 : 1)
            }
        }
    }

    private func learningPillLabel(
        icon: String?,
        title: LocalizedStringKey,
        active: Bool
    )
        -> some View
    {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.tujiIcon(11, weight: .bold))
            }
            Text(title)
                .font(.tujiLabel)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s3)
        .frame(height: 30)
        .background(
            active ? Color.tujiInk.opacity(0.64) : Color.tujiAccumulation,
            in: .rect(cornerRadius: Radius.r0)
        )
    }

    private var isOwnItem: Bool {
        self.relationship == .mine
    }
}

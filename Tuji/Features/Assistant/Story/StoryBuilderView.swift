// 情境故事 — the screen. Reached from 助手.
//
// One page, top to bottom in the order of the decision: 單字, 場地, 情景,
// 難度. The button at the bottom is the only thing that spends points, and it
// says what it costs before it is tapped. Tapping it hands the page to the
// story at once, and the story arrives there; closing it comes back to the
// same choices, as does a write that fails before any of the story came in.

import SwiftUI

struct StoryBuilderView: View {
    @Environment(StudyFocus.self) private var studyFocus

    @State private var model: StoryBuilderModel
    @State private var picking = false

    init(model: StoryBuilderModel = StoryBuilderModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back, compactTitle: Text("情境故事"), showsRule: true)
            if self.model.story != nil || self.model.writing == .writing {
                StoryReaderView(
                    story: self.model.story,
                    language: self.model.storyLanguage,
                    picked: self.model.picked,
                    writing: self.model.writing
                ) {
                    self.model.closeStory()
                }
            } else {
                self.form
                self.writeBar
            }
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: self.model.offerRevision) { await self.model.loadOffer() }
        .sheet(isPresented: self.$picking) {
            StoryItemPicker(model: self.model)
        }
        .onAppear { self.studyFocus.enter() }
        .onDisappear {
            self.studyFocus.exit()
            self.model.stop()
        }
    }

    // MARK: - 選項

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                HStack(alignment: .center, spacing: Space.s2) {
                    Mascot(pose: .face, size: 36)
                    Text("選幾個單字，開始一段對話")
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk)
                }
                self.items
                switch self.model.offerPhase {
                case .failed:
                    TujiBlankState(kind: .failed, retry: { await self.model.loadOffer() })
                case .loaded:
                    if let offer = self.model.offer {
                        self.choices(offer)
                    }
                default:
                    TujiProgressBar(progress: nil).frame(width: 40)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
        }
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            self.heading(tujiLocalized("單字（最多 \(StoryBuilderModel.maxItems) 個）"))
            if !self.model.picked.isEmpty {
                FlowLayout(spacing: Space.s2) {
                    ForEach(self.model.picked) { word in
                        Button {
                            self.model.toggle(word)
                        } label: {
                            HStack(spacing: Space.s1) {
                                Text(verbatim: word.word)
                                Image(systemName: "xmark")
                                    .font(.tujiIcon(11, weight: .bold))
                            }
                            .chipLabel(selected: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("移除 \(word.word)"))
                    }
                }
            }
            if self.model.canPickMore {
                Button {
                    self.picking = true
                } label: {
                    HStack(spacing: Space.s1) {
                        Image(systemName: "plus")
                            .font(.tujiIcon(13, weight: .bold))
                        Text("選單字")
                    }
                    .chipLabel(selected: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func choices(_ offer: StoryOffer) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            self.heading(tujiLocalized("場地"))
            FlowLayout(spacing: Space.s2) {
                ForEach(offer.scenes) { scene in
                    self.chip(scene.label, selected: scene.id == self.model.sceneId) {
                        self.model.chooseScene(scene.id)
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: Space.s2) {
            self.heading(tujiLocalized("情景"))
            FlowLayout(spacing: Space.s2) {
                ForEach(self.model.situations) { situation in
                    self.chip(situation.label, selected: situation.id == self.model.situationId) {
                        self.model.chooseSituation(situation.id)
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: Space.s2) {
            self.heading(tujiLocalized("難度"))
            VStack(spacing: 0) {
                ForEach(offer.levels) { level in
                    Button {
                        self.model.chooseLevel(level.id)
                    } label: {
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: level.label)
                                    .font(.tujiBody(.strong))
                                    .foregroundStyle(.tujiInk)
                                Text(verbatim: level.hint)
                                    .font(.tujiBodySm)
                                    .foregroundStyle(.tujiInk3)
                            }
                            Spacer(minLength: Space.s2)
                            if level.id == self.model.levelId {
                                Image(systemName: "checkmark")
                                    .font(.tujiIcon(15, weight: .bold))
                                    .foregroundStyle(.tujiInk)
                            }
                        }
                        .frame(minHeight: 56)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(level.id == self.model.levelId ? .isSelected : [])
                    Rectangle().fill(.tujiRule).frame(height: Border.bw1)
                }
            }
        }
    }

    // MARK: - 生成

    private var writeBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let note = self.note {
                Text(verbatim: note)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            BBtn(title: "生成故事", fullWidth: true) {
                self.model.start()
            }
            .disabled(!self.model.canWrite)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(alignment: .top) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    /// The price before the tap, or why the last tap produced nothing.
    private var note: String? {
        if case let .failed(failure) = self.model.writing {
            return Self.sentence(for: failure)
        }
        guard self.model.balanceKnown, let offer = self.model.offer else { return nil }
        let (low, high, held) = (offer.minPoints, offer.maxPoints, offer.available)
        if !self.model.canAfford {
            return tujiLocalized("至少要有 \(high) 點罐頭點數才能寫故事，你現在有 \(held) 點。")
        }
        return tujiLocalized("依實際用量扣罐頭點數，通常 \(low)–\(high) 點。你現在有 \(held) 點。")
    }

    static func sentence(for failure: StoryBuilderModel.Failure) -> String {
        switch failure {
        case .insufficientPoints: tujiLocalized("罐頭點數不夠寫這個故事。沒有扣點。")
        case .busy: tujiLocalized("寫得有點快，等一下再試。沒有扣點。")
        case .offline: tujiLocalized("連不上網路，寫不了故事。沒有扣點。")
        case .unavailable: tujiLocalized("現在不能寫故事。沒有扣點。")
        case .itemsChanged: tujiLocalized("選的單字有變動，請重新選一次。沒有扣點。")
        case .failed: tujiLocalized("這次沒寫好，再試一次。沒有扣點。")
        }
    }

    // MARK: - Bits

    private func heading(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.tujiLabel)
            .tracking(0.5)
            .foregroundStyle(.tujiInk3)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label).chipLabel(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    /// The 助手 chip: a ground, not an outline; a chosen one is ink.
    func chipLabel(selected: Bool) -> some View {
        self.font(.tujiBodySm(.strong))
            .foregroundStyle(selected ? Color.tujiPaper : .tujiInk)
            .padding(.horizontal, Space.s3)
            .frame(minHeight: 44)
            .background(selected ? Color.tujiInk : .tujiPaper2)
            .contentShape(.rect)
    }
}

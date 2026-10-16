// 圖鑑主題對話 — the pieces of the conversation.
//
// Moira's turn is her line, its translation and reading (each switchable on
// its own), and — on the newest turn only — 「跟著說」
// with its options, plus whatever 示範回答 / 簡單一點 opened. Older
// turns stay readable but offer nothing to tap that would answer them.
//
// No `Spacer` beside a sentence with furigana: `FuriganaSentence` is a custom
// layout, and a custom layout beside a spacer is offered half the row.

import SwiftUI

/// A sentence in the language being learned, with its reading and translation as the person chose.
struct ChatSentence: View {
    let text: ChatTargetText
    var showTranslation = true
    var showReading = true
    var font: Font = .tujiBody(.strong)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if self.showReading, let furigana = self.text.furigana, !furigana.isEmpty {
                FuriganaSentence(segments: furigana, font: self.font)
            } else {
                Text(verbatim: self.text.text)
                    .font(self.font)
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
                if self.showReading, let reading = self.text.reading {
                    Text(verbatim: reading)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if self.showTranslation, let translation = self.text.translation {
                Text(verbatim: translation)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }
}

struct TopicDividerRow: View {
    let name: String

    var body: some View {
        HStack(spacing: Space.s2) {
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
            Text("主題：\(self.name)")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .fixedSize()
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
        .padding(.vertical, Space.s1)
        .accessibilityElement(children: .combine)
    }
}

struct UserTurnRow: View {
    let text: String

    var body: some View {
        Text(verbatim: self.text)
            .font(.tujiBody)
            .foregroundStyle(.tujiInk)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(.tujiBrandPrimary.opacity(0.35))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Space.s5)
    }
}

/// The answer on its way, or the one that did not get there.
struct OutgoingRow: View {
    let outgoing: TopicChatModel.Outgoing
    let retry: () -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.s1) {
            UserTurnRow(text: self.outgoing.text)
                .opacity(self.outgoing.status == .sending ? 0.6 : 1)
            switch self.outgoing.status {
            case .sending:
                EmptyView()
            case .stopped:
                self.actions(note: tujiLocalized("已停止，這則沒有送到 Moira。"))
            case let .failed(failure):
                self.actions(note: TopicChatView.sentence(for: failure))
            }
        }
    }

    private func actions(note: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: note)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s4) {
                Button("改一下", action: self.edit)
                    .foregroundStyle(.tujiInk2)
                Button("再送一次", action: self.retry)
                    .foregroundStyle(.tujiInk)
            }
            .font(.tujiBodySm(.strong))
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        }
    }
}

struct AITurnRow: View {
    let turn: ChatAITurn
    let language: TargetLanguage
    let showTranslation: Bool
    let showReading: Bool
    /// The newest turn, open for an answer: the only one with answer actions.
    let isLatest: Bool
    let exampleShown: Bool
    let fill: (String, ChatSupport) -> Void

    private static let faceSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let scene = self.turn.scene {
                Text(verbatim: scene)
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: Space.s2) {
                Mascot(pose: .face, size: Self.faceSize)
                    .accessibilityLabel(Text(verbatim: "Moira"))
                HStack(alignment: .top, spacing: Space.s2) {
                    ChatSentence(
                        text: self.turn.line,
                        showTranslation: self.showTranslation,
                        showReading: self.showReading
                    )
                    PronunciationButton(
                        subject: .sentence(self.turn.line.text, language: self.language),
                        size: 28,
                        ground: .tujiPaper
                    )
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(.tujiPaper2)
            }
            .padding(.trailing, Space.s5)
            if let simpler = self.turn.simpler {
                self.simplerBlock(simpler)
            }
            if self.isLatest {
                if let pattern = self.turn.pattern {
                    FollowAlongCard(
                        pattern: pattern,
                        options: self.turn.options,
                        showTranslation: self.showTranslation,
                        fill: { self.fill($0, .option) }
                    )
                } else if !self.turn.options.isEmpty {
                    OptionList(options: self.turn.options, showTranslation: self.showTranslation) { self.fill(
                        $0,
                        .option
                    ) }
                }
                if self.exampleShown, let example = self.turn.example {
                    self.example(example)
                }
            }
        }
        .padding(.leading, 0)
    }

    private func simplerBlock(_ simpler: ChatAITurn.Simpler) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("簡單一點")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiBrandSecondary)
            Text(verbatim: simpler.note)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
            if let line = simpler.line {
                ChatSentence(text: line, showTranslation: self.showTranslation, showReading: self.showReading)
            }
            if self.isLatest, !simpler.options.isEmpty {
                OptionList(options: simpler.options, showTranslation: self.showTranslation) { self.fill($0, .simplify) }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(.tujiBrandSecondary).frame(width: Border.bw2)
        }
        .padding(.leading, Self.faceSize + Space.s2)
    }

    private func example(_ example: ChatTargetText) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("示範回答")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            ChatSentence(text: example, showTranslation: self.showTranslation, showReading: self.showReading)
            Button {
                self.fill(example.text, .example)
            } label: {
                Text("填入草稿，改成自己的")
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
        .padding(.leading, Self.faceSize + Space.s2)
    }
}

/// 「跟著說」: the structure with its blank marked by more than colour — an
/// underlined, bracketed gap that VoiceOver reads as 「空格」.
struct FollowAlongCard: View {
    let pattern: ChatPattern
    let options: [ChatOption]
    let showTranslation: Bool
    let fill: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("跟著說")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiBrandSecondary)
            Text(self.template)
                .font(.tujiBody(.strong))
                .foregroundStyle(.tujiInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: self.spokenTemplate))
            if self.showTranslation, let translation = self.pattern.translation {
                Text(verbatim: translation)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
            }
            if !self.options.isEmpty {
                OptionList(options: self.options, showTranslation: self.showTranslation, fill: self.fill)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper2)
        .padding(.leading, 32 + Space.s2)
    }

    private static let blank = /＿＿|___/

    private var template: AttributedString {
        var result = AttributedString()
        let source = self.pattern.template
        guard let match = source.firstMatch(of: Self.blank) else {
            return AttributedString(source)
        }
        result += AttributedString(String(source[..<match.range.lowerBound]))
        var gap = AttributedString(" ［\u{2003}\u{2003}］ ")
        gap.underlineStyle = .single
        gap.backgroundColor = .tujiBrandPrimary.opacity(0.5)
        result += gap
        result += AttributedString(String(source[match.range.upperBound...]))
        return result
    }

    private var spokenTemplate: String {
        self.pattern.template.replacing(Self.blank, with: tujiLocalized("（空格）"))
    }
}

/// Up to three answers. A tap fills the draft with the whole sentence; nothing is sent.
struct OptionList: View {
    let options: [ChatOption]
    let showTranslation: Bool
    let fill: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ForEach(self.options, id: \.self) { option in
                Button {
                    self.fill(option.answer.text)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option.answer.text)
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if self.showTranslation, let translation = option.answer.translation {
                            Text(verbatim: translation)
                                .font(.tujiLabel)
                                .foregroundStyle(.tujiInk3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(.tujiPaper)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("填入草稿，不會直接送出"))
            }
        }
    }
}

/// 幫我接話 — 示範回答 only opens what came with the turn; 簡單一點 and
/// 換個問題 generate, free, a couple of times between answers.
struct SupportTray: View {
    let model: TopicChatModel
    let generate: (TopicChatAssistKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            FlowLayout(spacing: Space.s2) {
                self.chip(
                    "示範回答",
                    selected: self.model.exampleShown,
                    enabled: self.model.latestTurn?.ai?.example != nil
                ) {
                    self.model.toggleExample()
                }
                self.chip(
                    "簡單一點",
                    selected: false,
                    enabled: self.model.canAssist && self.model.latestTurn?.ai?.simpler == nil
                ) { self.generate(.simplify) }
                self.chip("換個問題", selected: false, enabled: self.model.canAssist) { self.generate(.another) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(
        _ title: LocalizedStringKey,
        selected: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.tujiBodySm(.strong))
                .foregroundStyle(selected ? Color.tujiPaper : enabled ? .tujiInk : .tujiInk3)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: 44)
                .background(selected ? Color.tujiInk : .tujiPaper2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

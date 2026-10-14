// 情境故事 — choosing the 圖鑑物品. The person's own cards first, then the
// official dictionary; a search ranks both the way 搜尋 does.

import SwiftUI

struct StoryItemPicker: View {
    @Environment(\.dismiss) private var dismiss

    let model: StoryBuilderModel
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: tujiLocalized("已選 \(self.model.picked.count)/\(StoryBuilderModel.maxItems)"))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                Spacer()
                Button {
                    self.dismiss()
                } label: {
                    Text("完成")
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s2)

            TextField("搜尋單字", text: self.$query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.tujiBody)
                .foregroundStyle(.tujiInk)
                .tint(.tujiInk)
                .padding(.horizontal, Space.s3)
                .frame(height: 48)
                .background(.tujiPaper2)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        let own = self.model.candidates.filter { $0.id.atlasItemId != nil }
                        let official = self.model.candidates.filter { $0.id.atlasItemId == nil }
                        if !own.isEmpty {
                            self.section(tujiLocalized("我的自製圖鑑"), own)
                        }
                        self.section(tujiLocalized("官方圖鑑"), official)
                    } else {
                        let matches = SearchVM.localMatches(trimmed, in: self.model.candidates)
                        if matches.isEmpty {
                            Text("找不到這個單字")
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                                .padding(.vertical, Space.s4)
                        } else {
                            self.section(nil, matches)
                        }
                    }
                }
                .padding(.horizontal, Space.s4)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.tujiPaper.ignoresSafeArea())
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func section(_ title: String?, _ words: [CardWord]) -> some View {
        if let title {
            Text(verbatim: title)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s1)
        }
        ForEach(words) { word in
            self.row(word)
            Rectangle().fill(.tujiRule).frame(height: Border.bw1)
        }
    }

    private func row(_ word: CardWord) -> some View {
        let picked = self.model.isPicked(word)
        let blocked = !picked && !self.model.canPickMore
        return Button {
            self.model.toggle(word)
        } label: {
            HStack(spacing: Space.s3) {
                Color.tujiPaper2
                    .frame(width: 44, height: 44)
                    .overlay {
                        WordPicture(url: word.imageURL, kind: word.imageKind, inset: Space.s1, glyphSize: 14)
                    }
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: word.word)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                    Text(verbatim: word.chinese)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: picked ? "checkmark.square.fill" : "square")
                    .font(.tujiIcon(20))
                    .foregroundStyle(picked ? Color.tujiInk : .tujiInk3)
            }
            .frame(minHeight: 60)
            .contentShape(.rect)
            .opacity(blocked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

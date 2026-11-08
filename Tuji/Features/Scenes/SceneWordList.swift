// 相關詞條 under a 問句: picture, headword, reading and meaning, one row per
// word. 進店前看一眼 pushes the word page; the practice screen opens a sheet,
// so coming back does not land on a fresh `.task` that replays the line.

import NukeUI
import SwiftUI

extension SceneQuestion {
    /// Reading `LiveEffectiveEntitlement` and the store from a view body keeps
    /// the locks and rows current as either loads.
    func relatedWords(in store: WordsStore, direction: LearningDirection) -> [SceneWord] {
        SceneWords.resolve(
            ids: self.wordIds,
            in: store.words,
            studyable: LiveEffectiveEntitlement.shared.membership?.studyableCategories,
            direction: direction
        )
    }
}

struct SceneWordList: View {
    enum Opening {
        case push
        case present((CardWord) -> Void)
    }

    let words: [SceneWord]
    let opening: Opening

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("相關詞條")
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
            ForEach(self.words) { item in
                switch self.opening {
                case .push:
                    NavigationLink(value: NavRoute.wordDetail(id: item.word.id)) { self.row(item) }
                        .buttonStyle(.plain)
                case let .present(open):
                    Button { open(item.word) } label: { self.row(item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ item: SceneWord) -> some View {
        let word = item.word
        let reading = word.reading.flatMap { $0 == word.word ? nil : $0 }
        return HStack(spacing: Space.s3) {
            LazyImage(url: word.imageURL) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.tujiPaper2
                }
            }
            .frame(width: 40, height: 40)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s1) {
                    Text(verbatim: word.word)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiInk)
                    if item.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.tujiIcon(11, weight: .semibold))
                            .foregroundStyle(.tujiInk3)
                            .accessibilityLabel(Text("學習這個主題需要永久會員"))
                    }
                }
                Text(verbatim: [reading, word.chinese].compactMap(\.self).joined(separator: " · "))
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
            }
            Spacer(minLength: Space.s2)
            TujiRowAccessory()
        }
        .frame(minHeight: 48)
        .contentShape(.rect)
    }
}

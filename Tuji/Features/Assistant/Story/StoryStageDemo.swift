// The 情境故事 stage with a sample story, for DEBUG builds only.

import SwiftUI

#if DEBUG
/// A finished story at a chosen place, for looking at the stage without
/// spending points. Launch with `-StoryStageDemo <sceneId>`.
struct StoryStageDemo: View {
    let sceneId: String

    static var requestedScene: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-StoryStageDemo") else { return nil }
        return args.indices.contains(index + 1) ? args[index + 1] : "supermarket"
    }

    var body: some View {
        // Same chrome as `StoryBuilderView`, so the stage gets the height it
        // has in the real flow.
        NavigationStack {
            VStack(spacing: 0) {
                TujiNavBar(leading: .back, compactTitle: Text("情境故事"), showsRule: true)
                StoryStageView(
                    story: Self.story,
                    sceneId: self.sceneId,
                    language: .ja,
                    picked: Self.picked,
                    writing: .idle,
                    close: {}
                )
            }
            .background(Color.tujiPaper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private static let picked = [
        CardWord(
            id: "demo-ringo", word: "りんご", chinese: "蘋果", imageUrl: "", category: "food",
            pronunciation: "ringo", targetLanguage: .ja
        ),
        CardWord(
            id: "demo-kau", word: "買う", chinese: "買", imageUrl: "", category: "daily",
            pronunciation: "kau", reading: "かう", targetLanguage: .ja
        )
    ]

    private typealias Ruby = [(String, String?)]
    private typealias Who = Story.Segment.Speaker

    private static func line(_ speaker: Who, _ text: String, _ ruby: Ruby?, _ tr: String?) -> Story.Segment {
        Story.Segment(
            speaker: speaker,
            text: text,
            furigana: ruby?.map { FuriganaSegment(text: $0.0, ruby: $0.1) },
            reading: nil,
            translation: tr,
            wordIds: []
        )
    }

    private static let tasty: Ruby = [("この", nil), ("りんご", nil), ("、", nil), ("美味", "おい"), ("しそうですね。", nil)]
    private static let howMany: Ruby = [("いくつ", nil), ("買", "か"), ("いますか。", nil)]
    private static let three: Ruby = [("三", "みっ"), ("つ", nil), ("買", "か"), ("いましょう。", nil)]

    // Sample story content, not interface copy: kept out of the `title:` call
    // so the localisation check does not read it as a key.
    private static let sampleTitle = "和Moira一起買蘋果"
    private static let sampleIntro = "你和Moira走進超市，在水果區看到一籃紅色的蘋果。你想買一些回家，Moira陪你一起挑選。"

    static let story = Story(
        title: sampleTitle,
        intro: sampleIntro,
        segments: [
            line(.cat, "このりんご、美味しそうですね。", tasty, "這個蘋果看起來很好吃呢。"),
            line(.you, "いくつ買いますか。", howMany, "要買幾個？"),
            line(.narrator, "Moira 拿起一顆蘋果，仔細看了看。", nil, nil),
            line(.cat, "三つ買いましょう。", three, "買三個吧。"),
            line(.you, "はい、そうしましょう。", nil, "好，就這麼辦。")
        ],
        wordNotes: nil
    )
}
#endif

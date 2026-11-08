// 圖鑑 → 場面 (場面練習方案 §3): which 問句 ask about a word, and which 場面
// use a topic's words. Both are read off the 問句's `wordIds`, so the content
// never names topics itself.

import Foundation

nonisolated struct SceneMention: Identifiable, Equatable {
    let scene: PracticeScene
    let questions: [SceneQuestion]

    var id: SceneID {
        self.scene.id
    }
}

nonisolated enum SceneLinks {
    /// The scenes whose 問句 reference `wordId`, each with those 問句. A word
    /// page opened from one scene leaves that scene out, so it does not lead
    /// back where the user came from.
    static func mentions(of wordId: String, in catalog: SceneCatalog, excluding: SceneID?) -> [SceneMention] {
        catalog.scenes.compactMap { scene in
            guard scene.id != excluding else { return nil }
            let questions = scene.questions.filter { $0.wordIds.contains(wordId) }
            return questions.isEmpty ? nil : SceneMention(scene: scene, questions: questions)
        }
    }

    /// Up to `limit` scenes that reference words of `topic`, those referencing
    /// the most first, ties in catalog order.
    static func scenes(
        forTopic topic: String,
        topicOf: [String: String],
        in catalog: SceneCatalog,
        limit: Int = 2
    )
        -> [PracticeScene]
    {
        let scenes = catalog.scenes
        let hits = scenes.map { scene in
            Set(scene.questions.flatMap(\.wordIds)).count { topicOf[$0] == topic }
        }
        return scenes.indices
            .filter { hits[$0] > 0 }
            .sorted { (hits[$1], $0) < (hits[$0], $1) }
            .prefix(limit)
            .map { scenes[$0] }
    }
}

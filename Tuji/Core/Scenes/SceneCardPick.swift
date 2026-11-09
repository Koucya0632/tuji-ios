// Which 場面 今天's card offers (場面練習方案 §3): one due for review today,
// else one half done, else the next one never opened. When every scene is
// done the card offers the last one practised, for 進店前看一眼.

import Foundation

nonisolated struct SceneCardPick: Equatable {
    enum State: Equatable {
        case notStarted
        /// `at` is the 1-based number of the question practice reopens on.
        case inProgress(at: Int)
        case reviewDue
        case allDone(SceneStatus)
    }

    let scene: PracticeScene
    let state: State
    /// One flag per question, in scene order: practised at least once.
    let practised: [Bool]
}

nonisolated enum SceneCards {
    /// `canPractise` leaves out scenes this account cannot open, so the card
    /// never leads to a lock.
    static func pick(
        _ scenes: [PracticeScene],
        book: SceneProgressBook,
        today: LocalDay,
        canPractise: (PracticeScene) -> Bool
    )
        -> SceneCardPick?
    {
        let open = scenes.filter(canPractise)
        let statuses = open.map { ($0, ScenePractice.status($0, book: book, today: today)) }
        func card(_ scene: PracticeScene, _ state: SceneCardPick.State) -> SceneCardPick {
            SceneCardPick(
                scene: scene,
                state: state,
                practised: scene.questions.map { book.progress($0.id).stage != .new }
            )
        }
        if let (scene, _) = statuses.first(where: { if case .reviewDue = $0.1 { true } else { false } }) {
            return card(scene, .reviewDue)
        }
        if let (scene, _) = statuses.first(where: { if case .inProgress = $0.1 { true } else { false } }) {
            let cursor = book.cursors[scene.id]
                ?? scene.questions.firstIndex { book.progress($0.id).stage == .new }
                ?? 0
            return card(scene, .inProgress(at: cursor + 1))
        }
        if let (scene, _) = statuses.first(where: { $0.1 == .notStarted }) {
            return card(scene, .notStarted)
        }
        let last = statuses.first { $0.0.id == book.lastSceneId } ?? statuses.first
        return last.map { card($0.0, .allDone($0.1)) }
    }
}

extension PracticeScene {
    /// About half a minute a question, rounded up: 6 questions is 3 minutes.
    nonisolated var minutes: Int {
        (self.questions.count + 1) / 2
    }
}

extension PracticeScene {
    /// From the third scene on, practice is for 永久會員 (場面練習方案 §2).
    /// 進店前看一眼 stays open to everyone.
    nonisolated func canPractise(_ tier: MembershipTier) -> Bool {
        switch self.access {
        case .free: true
        case .lifetime: tier != .free
        }
    }
}

// Where 個人詞表 screens push to. Its own route type rather than three more
// `NavRoute` cases: the tab stacks hold a `NavigationPath`, which takes any
// Hashable, and the shared destination switch was already at its complexity
// ceiling.

import SwiftUI

enum WordListRoute: Hashable {
    case lists
    case list(id: String)
    case study(listId: String, mode: StudyMode)
}

extension View {
    func wordListDestinations() -> some View {
        self.navigationDestination(for: WordListRoute.self) { route in
            switch route {
            case .lists:
                WordListsView()
            case let .list(id):
                WordListDetailView(listId: id)
            // No 再來一輪: the follow-up CTA counts every word due, not this
            // list's.
            case let .study(listId, mode):
                StudyLauncherView(
                    mode: mode,
                    queues: WordListStudyQueue(listId: listId),
                    allowsAnotherRound: false
                )
            }
        }
    }
}

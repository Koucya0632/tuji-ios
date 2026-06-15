// Which side of the study flow the user is entering — drives the queue
// fetch (mode=new vs mode=review) and which flow view is pushed.
// Lifted out of the now-deleted StudyLandingView so NavRoute (in
// Navigation/) can stay decoupled from any specific feature surface.

import Foundation

enum StudyMode: Hashable {
    case new
    case review

    /// URL path component used by /api/study/queue?mode=...
    var asPath: String {
        switch self {
        case .new: "new"
        case .review: "review"
        }
    }
}

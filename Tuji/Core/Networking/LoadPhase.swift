// Where one account-scoped read stands.
//
// Every learning store answered "has this arrived?" its own way: `MasteryStore`
// set `loaded` on failure too and then never retried, `ProgressStore` and
// `StudyStatsStore` had no flag at all, and the screens made one up —
// `!categoryProgress.isEmpty` on 首頁, `stats == nil` in TodayDecisions. So a
// failed mastery read rendered 「還沒有學習紀錄」 for the whole session, the
// exact false claim `MeProgressSections` exists to avoid.
//
// This is not the staleness rule (see LoadFlights.swift) and not "how one
// request runs". It is the one fact a screen needs: is what I am looking at the
// account's answer?

import Foundation

enum LoadPhase: Equatable {
    /// Nothing asked yet — or the account changed and everything was dropped.
    case idle
    /// The first answer is on its way. A reload over data already shown stays
    /// `.loaded`: the old answer is still the account's, just not the newest.
    case loading
    /// An answer arrived and is on screen. It may be empty; empty is an answer.
    case loaded
    /// The first answer never arrived. Not an empty answer — a missing one.
    case failed

    /// What a reload that is about to start makes of the current phase.
    var reloading: LoadPhase {
        self == .loaded ? .loaded : .loading
    }

    /// What a reload that failed makes of the phase it started from. Data
    /// already shown stays shown; nothing shown stays nothing.
    var afterFailure: LoadPhase {
        self == .loaded ? .loaded : .failed
    }
}

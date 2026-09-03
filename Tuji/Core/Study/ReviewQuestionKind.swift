// Which question 複習 is asking about the card in front of the user.
//
// 複習 had exactly one shape for its whole life — a picture and four word
// labels — so the shape was never named and `activity: "mcq"` was a literal at
// the one call site that sent it. 聽句 (see CONTEXT.md) is the second, so the
// choice becomes a value the coordinator makes per presentation.
//
// The case names deliberately do NOT match the wire values. `mcq` names the
// *form* of the question (four options) while `listening` names the *sensory
// channel*; a single enum whose cases are named on two different axes leaves
// the next person adding a third with no way to know which axis to pick. Both
// cases here are named for what the user does, and `asActivity` keeps the wire
// vocabulary — the same split `StudyMode.asPath` already makes.

import Foundation

enum ReviewQuestionKind: Hashable, CaseIterable {
    /// A picture, and four word labels to choose between.
    case pickWord
    /// The word's example sentence blurred, its audio, and two pictures.
    case hearSentence

    /// `study_logs.activity`. Both values are already in the server's
    /// `VALID_ACTIVITIES` set *and* the table's CHECK constraint, so neither
    /// needs a migration.
    var asActivity: String {
        switch self {
        case .pickWord: "mcq"
        case .hearSentence: "listening"
        }
    }
}

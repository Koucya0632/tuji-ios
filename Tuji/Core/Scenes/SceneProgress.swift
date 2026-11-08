// Where one account stands on each 問句, and what to practise next.
//
// A 問句 goes new → awaiting review (due the next local day) → reviewed, once.
// It is kept apart from the word SRS on purpose (場面練習方案 §5): a 問句 is
// learnt when you understand it in the shop, not when a forgetting curve says so.
//
// Everything here is a pure function of the progress book, the content and a
// day, so the scheduling rules are tested without a store or a clock.

import Foundation

/// A calendar day on this device. Stored as `yyyy-MM-dd`, so a review due
/// "tomorrow" stays tomorrow when the phone changes time zone on landing.
nonisolated struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    func adding(days: Int, calendar: Calendar) -> LocalDay {
        let start = calendar.date(from: DateComponents(year: self.year, month: self.month, day: self.day)) ?? .distantPast
        return LocalDay(calendar.date(byAdding: .day, value: days, to: start) ?? start, calendar: calendar)
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", self.year, self.month, self.day)
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad day \(raw)"))
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }
}

nonisolated enum QuestionStage: Hashable, Codable, Sendable {
    case new
    case awaitingReview(due: LocalDay)
    case reviewed
}

nonisolated struct QuestionProgress: Hashable, Codable, Sendable {
    var stage: QuestionStage = .new
    /// Every phrasing this account has practised, so a review never repeats one.
    var usedPhrasingIds: Set<PhrasingID> = []
}

/// One account's whole 場面練習 record: the file `SceneProgressStore` keeps.
nonisolated struct SceneProgressBook: Hashable, Codable, Sendable {
    var questions: [SceneQuestionID: QuestionProgress] = [:]
    /// Index into the scene's questions of the one to open next. Set as a
    /// question is shown, so quitting mid-scene comes back to that question.
    var cursors: [SceneID: Int] = [:]

    func progress(_ id: SceneQuestionID) -> QuestionProgress {
        self.questions[id] ?? QuestionProgress()
    }
}

nonisolated enum PracticeMode: Hashable, Sendable {
    /// Never practised. The clear phrasing, with slow playback and a transcript.
    case first
    /// Due today. A phrasing this account has not heard.
    case review
    /// Nothing owed today; practised again without moving its stage.
    case rehearsal
}

nonisolated struct PracticeStep: Hashable, Sendable {
    let questionIndex: Int
    let mode: PracticeMode
    let phrasing: Phrasing
}

/// What the scene list and the scene page say about a scene.
nonisolated enum SceneStatus: Hashable, Sendable {
    case notStarted
    case inProgress(practised: Int, total: Int)
    case reviewDue(count: Int)
    /// Every question practised, the earliest review still ahead.
    case reviewLater(due: LocalDay)
    case complete
}

nonisolated enum ScenePractice {
    static func mode(for progress: QuestionProgress, today: LocalDay) -> PracticeMode {
        switch progress.stage {
        case .new: .first
        case let .awaitingReview(due) where due <= today: .review
        case .awaitingReview, .reviewed: .rehearsal
        }
    }

    /// First practice takes the `first` phrasing. A review takes a review
    /// phrasing this account has not used, the fast one with ambience first. A
    /// rehearsal before the review is due repeats the first phrasing, so it does
    /// not spend tomorrow's.
    static func phrasing(for question: SceneQuestion, progress: QuestionProgress, mode: PracticeMode) -> Phrasing? {
        let first = question.firstPhrasing
        switch (mode, progress.stage) {
        case (.first, _), (.rehearsal, .new), (.rehearsal, .awaitingReview):
            return first
        case (.review, _), (.rehearsal, .reviewed):
            let reviews = question.phrasings
                .filter { $0.role == .review }
                .enumerated()
                .sorted { ($0.element.isHardest ? 0 : 1, $0.offset) < ($1.element.isHardest ? 0 : 1, $1.offset) }
                .map(\.element)
            return reviews.first { !progress.usedPhrasingIds.contains($0.id) } ?? reviews.first ?? first
        }
    }

    /// The questions to practise now, starting from the scene's cursor and
    /// wrapping around. Only what is owed today (new or due) when anything is;
    /// otherwise the whole scene as a rehearsal.
    static func plan(_ scene: PracticeScene, book: SceneProgressBook, today: LocalDay) -> [PracticeStep] {
        let all = scene.questions.enumerated().compactMap { index, question -> PracticeStep? in
            let progress = book.progress(question.id)
            let mode = self.mode(for: progress, today: today)
            guard let phrasing = self.phrasing(for: question, progress: progress, mode: mode) else { return nil }
            return PracticeStep(questionIndex: index, mode: mode, phrasing: phrasing)
        }
        let owed = all.filter { $0.mode != .rehearsal }
        let steps = owed.isEmpty ? all : owed
        let cursor = book.cursors[scene.id] ?? 0
        let start = steps.firstIndex { $0.questionIndex >= cursor } ?? 0
        return Array(steps[start...] + steps[..<start])
    }

    /// The progress after `step` is answered.
    static func completing(
        _ progress: QuestionProgress,
        step: PracticeStep,
        today: LocalDay,
        calendar: Calendar
    ) -> QuestionProgress {
        var next = progress
        next.usedPhrasingIds.insert(step.phrasing.id)
        switch step.mode {
        case .first: next.stage = .awaitingReview(due: today.adding(days: 1, calendar: calendar))
        case .review: next.stage = .reviewed
        case .rehearsal: break
        }
        return next
    }

    static func status(_ scene: PracticeScene, book: SceneProgressBook, today: LocalDay) -> SceneStatus {
        let stages = scene.questions.map { book.progress($0.id).stage }
        let fresh = stages.filter { $0 == .new }.count
        let dues = stages.compactMap { stage -> LocalDay? in
            if case let .awaitingReview(due) = stage { return due }
            return nil
        }
        let dueNow = dues.filter { $0 <= today }.count
        if fresh == stages.count { return .notStarted }
        if dueNow > 0 { return .reviewDue(count: dueNow) }
        if fresh > 0 { return .inProgress(practised: stages.count - fresh, total: stages.count) }
        if let next = dues.min() { return .reviewLater(due: next) }
        return .complete
    }
}

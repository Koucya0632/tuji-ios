import Foundation

enum StudyReportIssueType: String, CaseIterable, Identifiable {
    case image
    case content
    case audio
    case answer
    case ui
    case other

    var id: String { self.rawValue }
}

struct StudyReportSnapshot: Encodable, Sendable {
    let word: String
    let chinese: String
    let imageUrl: String
    let pronunciation: String
    let category: String
    let cardType: String?
    let deckKey: String?
    let choices: [String]
    let spellingChoices: [String]
    let displayedSpelling: String?
}

struct StudyReportDraft: Identifiable {
    let id: UUID
    let item: StudyQueueItem
    let mode: String
    let phase: String
    let selectedAnswer: String?
    let uiLang: String
    let displayedSpelling: String?

    init(
        item: StudyQueueItem,
        mode: String,
        phase: String,
        selectedAnswer: String?,
        uiLang: String,
        displayedSpelling: String? = nil
    ) {
        self.id = UUID()
        self.item = item
        self.mode = mode
        self.phase = phase
        self.selectedAnswer = selectedAnswer
        self.uiLang = uiLang
        self.displayedSpelling = displayedSpelling
    }

    var snapshot: StudyReportSnapshot {
        StudyReportSnapshot(
            word: self.item.word.word,
            chinese: self.item.word.chinese,
            imageUrl: self.item.word.imageUrl,
            pronunciation: self.item.word.pronunciation,
            category: self.item.word.category,
            cardType: self.item.card.cardType,
            deckKey: self.item.card.deckKey,
            choices: self.item.choices ?? [],
            spellingChoices: self.item.spellingChoices ?? [],
            displayedSpelling: self.displayedSpelling
        )
    }
}

nonisolated struct StudyReportPayload: Encodable, Sendable {
    let requestId: String
    let wordId: String
    let cardId: Int
    let issueType: String
    let description: String
    let mode: String
    let phase: String
    let selectedAnswer: String?
    let platform: String
    let appVersion: String
    let uiLang: String
    let snapshot: StudyReportSnapshot
}

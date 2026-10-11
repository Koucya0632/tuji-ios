// 校正表單 — what the user settles on before 確認並生成卡片: the candidate they
// picked and the names they may have corrected.
//
// A value, so its rules can be asked without a screen or a server: which fields
// still hold the AI's guess, when the form is complete, and what a confirm
// sends. Which second field is on screen is not decided here — that is
// `CaptureCorrectionFields`, and the caller passes its answer in.

import Foundation

struct CaptureCorrectionForm: Equatable {
    /// What the chosen candidate left in each field, so the form can mark a
    /// value as the AI's guess until the user changes it.
    struct Suggestion: Equatable {
        var lemma: String
        var zhHant: String
        var gloss: String
    }

    enum Field { case lemma, zhHant, gloss }

    var lemma = ""
    var displayZhHant = ""
    /// The ja/en meaning a cross-language capture edits; empty otherwise.
    var displayGloss = ""
    private(set) var selectedCandidateId: String?
    private(set) var suggestion: Suggestion?

    /// Tapping a chip is an explicit choice, so it replaces whatever the fields hold.
    mutating func select(_ candidate: CreditCandidate) {
        self.selectedCandidateId = candidate.id
        self.lemma = candidate.label
        self.displayZhHant = candidate.zhHant
        self.displayGloss = candidate.gloss ?? ""
        self.suggestion = .init(lemma: self.lemma, zhHant: self.displayZhHant, gloss: self.displayGloss)
    }

    func isStillSuggested(_ field: Field) -> Bool {
        guard let s = self.suggestion else { return false }
        return switch field {
        case .lemma: !s.lemma.isEmpty && s.lemma == self.lemma
        case .zhHant: !s.zhHant.isEmpty && s.zhHant == self.displayZhHant
        case .gloss: !s.gloss.isEmpty && s.gloss == self.displayGloss
        }
    }

    /// A candidate is chosen and the card has a name. The Chinese name is
    /// required even where it is not on screen: it arrives with the candidate.
    var isComplete: Bool {
        self.selectedCandidateId != nil && !Self.trim(self.lemma).isEmpty && !Self.trim(self.displayZhHant).isEmpty
    }

    /// The lemma, if the account already has a card by that name. A warning,
    /// never a refusal — two cards for one word is the user's call.
    func duplicate(among owned: [String]) -> String? {
        let trimmed = Self.trim(self.lemma)
        guard !trimmed.isEmpty else { return nil }
        let exists = owned.contains { Self.trim($0).caseInsensitiveCompare(trimmed) == .orderedSame }
        return exists ? trimmed : nil
    }

    /// What 確認並生成卡片 sends, given the form the user actually saw.
    ///
    /// The gloss travels only when its field was on screen; elsewhere the
    /// server keeps the candidate's. The Chinese name is withheld once the card
    /// is renamed on a form that never showed it (`chineseNameToSend`).
    func request(operationId: String, second: CaptureSecondField) -> CreditConfirmRequest? {
        guard self.isComplete, let candidateId = self.selectedCandidateId else { return nil }
        let gloss = Self.trim(self.displayGloss)
        return CreditConfirmRequest(
            operationId: operationId,
            candidateId: candidateId,
            lemma: Self.trim(self.lemma),
            displayZhHant: CaptureCorrectionFields.chineseNameToSend(
                second: second,
                lemma: self.lemma,
                suggestedLemma: self.suggestion?.lemma,
                zhHant: Self.trim(self.displayZhHant)
            ),
            displayGloss: second == .gloss && !gloss.isEmpty ? gloss : nil
        )
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

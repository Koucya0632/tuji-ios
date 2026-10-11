// 校正表單 as a value: what the AI guessed, when the form is complete, and
// what a confirm sends for the form the user actually saw.

import Foundation
import Testing
@testable import Tuji

struct CaptureCorrectionFormTests {
    private let cat = CreditCandidate(id: "c1", level: "primary", label: "cat", zhHant: "貓", gloss: "ねこ")

    @Test
    func choosingACandidateFillsTheFormAndEditsLeaveTheSuggestion() {
        var form = CaptureCorrectionForm()
        #expect(!form.isComplete)
        form.select(self.cat)
        #expect(form.lemma == "cat")
        #expect(form.displayZhHant == "貓")
        #expect(form.isStillSuggested(.lemma))
        form.lemma = "kitten"
        #expect(!form.isStillSuggested(.lemma))
        #expect(form.isStillSuggested(.zhHant))
        // Picking another chip is an explicit choice: it replaces the edit.
        form.select(CreditCandidate(id: "c2", level: "fine", label: "tabby", zhHant: "虎斑貓", gloss: "tabby cat"))
        #expect(form.lemma == "tabby")
        #expect(form.displayGloss == "tabby cat")
        #expect(form.selectedCandidateId == "c2")
        form.lemma = "  "
        #expect(!form.isComplete)
    }

    @Test
    func theRequestCarriesTrimmedNamesAndOnlyTheGlossThatWasOnScreen() throws {
        var form = CaptureCorrectionForm()
        form.select(self.cat)
        form.lemma = "  cat \n"
        form.displayGloss = " ネコ "

        let chinese = try #require(form.request(operationId: "op-1", second: .chineseName))
        #expect(chinese == CreditConfirmRequest(
            operationId: "op-1", candidateId: "c1", lemma: "cat", displayZhHant: "貓", displayGloss: nil
        ))
        #expect(form.request(operationId: "op-1", second: .gloss)?.displayGloss == "ネコ")
        #expect(form.request(operationId: "op-1", second: .hidden)?.displayGloss == nil)
    }

    @Test
    func aRenameOnAFormWithoutTheChineseFieldSendsNoChineseName() {
        var form = CaptureCorrectionForm()
        form.select(self.cat)
        form.lemma = "dog"
        #expect(form.request(operationId: "op-1", second: .hidden)?.displayZhHant == nil)
        #expect(form.request(operationId: "op-1", second: .gloss)?.displayZhHant == nil)
        // On a Chinese interface the name was on screen, so it is the user's answer.
        #expect(form.request(operationId: "op-1", second: .chineseName)?.displayZhHant == "貓")
    }

    @Test
    func anIncompleteFormSendsNothing() {
        var form = CaptureCorrectionForm()
        #expect(form.request(operationId: "op-1", second: .chineseName) == nil)
        form.select(self.cat)
        form.lemma = ""
        #expect(form.request(operationId: "op-1", second: .chineseName) == nil)
    }

    @Test
    func aDuplicateNameIsFoundWhateverItsCaseOrPadding() {
        var form = CaptureCorrectionForm()
        form.select(self.cat)
        #expect(form.duplicate(among: ["Cat ", "dog"]) == "cat")
        #expect(form.duplicate(among: ["dog"]) == nil)
        form.lemma = " "
        #expect(form.duplicate(among: [" "]) == nil)
    }
}

// Pins AtlasCaptureVM's pure pipeline rules: candidate auto-apply vs explicit
// chip taps, rank/level selection, submit gating, and the confirm-payload
// fallbacks. Also guards the NUMERIC-as-string confidence decode that has
// bitten the atlas routes before (資料解析失敗).

import Foundation
import Testing
@testable import Tuji

struct AtlasCaptureVMTests {
    private func candidate(
        id: String = "c1",
        level: String = "primary",
        label: String = "cat",
        zhHant: String? = "貓",
        gloss: String? = nil,
        confidence: String = "0.9",
        rank: Int = 1
    ) throws
        -> AtlasCandidate
    {
        var fields = [
            "\"id\": \"\(id)\"",
            "\"level\": \"\(level)\"",
            "\"label\": \"\(label)\"",
            "\"normalizedLabel\": \"\(label)\"",
            "\"confidence\": \(confidence)",
            "\"rank\": \(rank)"
        ]
        if let zhHant {
            fields.append("\"zhHant\": \"\(zhHant)\"")
        }
        if let gloss {
            fields.append("\"gloss\": \"\(gloss)\"")
        }
        let json = "{ \(fields.joined(separator: ", ")) }"
        return try JSONDecoder().decode(AtlasCandidate.self, from: Data(json.utf8))
    }

    @Test
    func levelKindMapsKnownTiersAndTolatesUnknown() throws {
        #expect(try self.candidate(level: "primary").levelKind == .primary)
        #expect(try self.candidate(level: "fine").levelKind == .fine)
        // Unknown future tier: decode succeeds, kind is just nil.
        #expect(try self.candidate(level: "ultra").levelKind == nil)
    }

    @Test
    func confidenceDecodesFromNumberOrNumericString() throws {
        // Raw-row atlas routes serialize Postgres NUMERIC as a JSON string.
        #expect(try self.candidate(confidence: "0.95").confidence == 0.95)
        #expect(try self.candidate(confidence: "\"0.9500\"").confidence == 0.95)
    }

    @Test
    func applyCandidatesPrefersFineAndSortsByRank() throws {
        let vm = AtlasCaptureVM()
        let coarse = try self.candidate(id: "coarse", level: "primary", label: "animal", rank: 1)
        let fine = try self.candidate(id: "fine", level: "fine", label: "tabby cat", rank: 2)
        vm.applyCandidates([fine, coarse], mode: .primary)
        #expect(vm.candidates.map(\.id) == ["coarse", "fine"])
        // The fine candidate wins the auto-apply even though it ranks later.
        #expect(vm.selectedCandidateId == "fine")
        #expect(vm.lemma == "tabby cat")
        // A successful recognition shows no banner; it just marks the mode active.
        #expect(vm.successMessage == nil)
        #expect(vm.activeMode == .primary)
    }

    @Test
    func applyCandidatesWithEmptyListLeavesFormAlone() {
        let vm = AtlasCaptureVM()
        vm.lemma = "typed"
        vm.applyCandidates([], mode: .escalate)
        #expect(vm.lemma == "typed")
        #expect(vm.selectedCandidateId == nil)
        // An empty result still surfaces the manual-entry guidance.
        #expect(vm.successMessage != nil)
        #expect(vm.activeMode == .escalate)
    }

    @Test
    func autoApplyNeverClobbersTypedNames() throws {
        let vm = AtlasCaptureVM()
        vm.lemma = "my name"
        vm.displayZhHant = "我的名字"
        try vm.apply(self.candidate(label: "cat", zhHant: "貓"))
        #expect(vm.lemma == "my name")
        #expect(vm.displayZhHant == "我的名字")
    }

    @Test
    func explicitChipTapOverwritesTypedNames() throws {
        let vm = AtlasCaptureVM()
        vm.lemma = "my name"
        vm.displayZhHant = "我的名字"
        try vm.apply(self.candidate(label: "cat", zhHant: "貓"), overwrite: true)
        #expect(vm.lemma == "cat")
        #expect(vm.displayZhHant == "貓")
    }

    @Test
    func zhFallsBackToLabelWhenCandidateHasNoZh() throws {
        let vm = AtlasCaptureVM()
        try vm.apply(self.candidate(label: "cat", zhHant: nil))
        #expect(vm.displayZhHant == "cat")
    }

    @Test
    func glossPrefillsOnlyWhenModelReturnsOne() throws {
        // Cross-language capture: the model returns a UI-language gloss →
        // prefill it. displayZhHant still carries the Chinese base.
        let withGloss = AtlasCaptureVM()
        try withGloss.apply(self.candidate(label: "cat", zhHant: "貓", gloss: "猫"))
        #expect(withGloss.displayGloss == "猫")
        #expect(withGloss.displayZhHant == "貓")

        // Monolingual / Chinese-UI capture: no gloss from the model → the
        // gloss field stays empty (never seeded with Chinese), so confirm
        // sends nil and display_ja/en aren't polluted.
        let noGloss = AtlasCaptureVM()
        try noGloss.apply(self.candidate(label: "cat", zhHant: "貓"))
        #expect(noGloss.displayGloss.isEmpty)
        #expect(noGloss.confirmPayload.displayGloss == nil)
    }

    @Test
    func canSubmitNeedsBothNames() {
        let vm = AtlasCaptureVM()
        #expect(!vm.canSubmit)
        vm.lemma = "cat"
        #expect(!vm.canSubmit)
        vm.displayZhHant = "貓"
        #expect(vm.canSubmit)
        vm.lemma = "   "
        #expect(!vm.canSubmit)
    }

    @Test
    func confirmPayloadFallsBackToLemmaAndDropsBlanks() {
        let vm = AtlasCaptureVM()
        vm.lemma = "cat"
        vm.displayZhHant = "貓"
        // No candidate applied: primaryLabel is empty → lemma stands in;
        // blank fineLabel/category drop to nil rather than sending "".
        let payload = vm.confirmPayload
        #expect(payload.primaryLabel == "cat")
        #expect(payload.fineLabel == nil)
        #expect(payload.category == nil)
        #expect(payload.partOfSpeech == "noun")
        #expect(payload.selectedCandidateId == nil)
    }

    @Test
    func candidateLabelFormatsWithAndWithoutZh() throws {
        let vm = AtlasCaptureVM()
        let withZh = try self.candidate(label: "cat", zhHant: "貓", confidence: "0.87")
        #expect(vm.candidateLabel(withZh) == "cat · 貓 · 87%")
        let noZh = try self.candidate(label: "cat", zhHant: nil, confidence: "0.87")
        #expect(vm.candidateLabel(noZh) == "cat · 87%")
    }
}

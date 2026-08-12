// Pins AtlasCaptureVM's pure pipeline rules: candidate auto-apply vs explicit
// chip taps, rank/level selection, submit gating, and the confirm-payload
// fallbacks. Also guards the NUMERIC-as-string confidence decode that has
// bitten the atlas routes before (資料解析失敗).
//
// The second half of the file is the part that used to be unreachable. Every
// test here once constructed a bare `AtlasCaptureVM()` against the live
// singleton, so upload, 識別 and the mode cache — the rule that protects the
// user's paid AI allowance — were never exercised, even though the seam and the
// fake to fill it both already existed. `requestRecognize` being synchronous and
// spawning a `Task {}` it dropped is what made that impossible rather than
// merely unwritten.

import Foundation
import Testing
@testable import Tuji

@MainActor
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
    func aiSuggestionMarkClearsWhenTheUserTypesOverIt() throws {
        let vm = AtlasCaptureVM()
        // Nothing applied yet: nothing is the model's.
        #expect(!vm.isStillSuggested(.lemma))

        try vm.apply(self.candidate(label: "cat", zhHant: "貓"), overwrite: true)
        #expect(vm.isStillSuggested(.lemma))
        #expect(vm.isStillSuggested(.zhHant))
        // No gloss on this candidate, so that field was never the model's.
        #expect(!vm.isStillSuggested(.gloss))

        vm.lemma = "kitten"
        #expect(!vm.isStillSuggested(.lemma))
        // Editing one field says nothing about the others.
        #expect(vm.isStillSuggested(.zhHant))
    }

    @Test
    func typingTheSuggestionBackRestoresTheMark() throws {
        // The mark compares values rather than remembering that an edit
        // happened: a field the user changed and changed back really does hold
        // the model's suggestion, and claiming otherwise would be a lie about
        // where the value came from.
        let vm = AtlasCaptureVM()
        try vm.apply(self.candidate(label: "cat", zhHant: "貓"), overwrite: true)
        vm.lemma = "kitten"
        #expect(!vm.isStillSuggested(.lemma))
        vm.lemma = "cat"
        #expect(vm.isStillSuggested(.lemma))
    }

    @Test
    func candidateLabelPrefersUiGlossAndFallsBackToChinese() throws {
        let vm = AtlasCaptureVM()
        let withGloss = try self.candidate(label: "猫", zhHant: "貓", gloss: "cat", confidence: "0.87")
        #expect(vm.candidateLabel(withGloss) == "猫 · cat · 87%")
        let chineseFallback = try self.candidate(label: "猫", zhHant: "貓", confidence: "0.87")
        #expect(vm.candidateLabel(chineseFallback) == "猫 · 貓 · 87%")
        let noMeaning = try self.candidate(label: "猫", zhHant: nil, confidence: "0.87")
        #expect(vm.candidateLabel(noMeaning) == "猫 · 87%")
    }

    // MARK: - Over the seam

    /// A VM standing on fakes end to end: the store over `FakeAtlasAuthoring`,
    /// a 生成佇列 that touches neither network nor disk, and a two-line
    /// `LanguageContext`.
    private func standUp(
        repository: FakeAtlasAuthoring = FakeAtlasAuthoring(),
        language: FakeLanguageContext = FakeLanguageContext(),
        queue: AtlasCaptureQueue? = nil
    )
        -> (vm: AtlasCaptureVM, store: AtlasStore, queue: AtlasCaptureQueue)
    {
        let store = AtlasStore(repository: repository)
        let queue = queue ?? AtlasCaptureQueue(
            cards: FakeCardGenerating(),
            journal: InMemoryCaptureJobJournal(),
            mutations: SpyAtlasMutationRefreshing(),
            doneLinger: .zero,
            celebrate: {}
        )
        return (AtlasCaptureVM(store: store, queue: queue, language: language), store, queue)
    }

    @Test
    func uploadCachesTheCandidatesThatRodeBackWithIt() async throws {
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = try AtlasFixtures.uploadResponse(
            candidates: [AtlasFixtures.candidate(id: "c1", label: "cat")]
        )
        let (vm, _, _) = self.standUp(repository: repository)

        await vm.handlePicked(data: Data([0xFF, 0xD8, 0xFF]))

        #expect(vm.uploadedImage?.id == "img-1")
        #expect(vm.lemma == "cat")
        // Recognition ran server-side inside the upload, so no separate call.
        #expect(repository.recognizeCalls.isEmpty)
    }

    @Test
    func aSecondTapOnTheSameModeSpendsNothing() async throws {
        // The result of a re-run barely differs, and every call comes out of the
        // user's monthly allowance.
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = try AtlasFixtures.uploadResponse(
            candidates: [AtlasFixtures.candidate(id: "c1", label: "cat")]
        )
        let (vm, _, _) = self.standUp(repository: repository)
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.primary)
        await vm.requestRecognize(.primary)

        #expect(repository.recognizeCalls.isEmpty)
        #expect(vm.activeMode == .primary)
    }

    @Test
    func eachDepthIsRecognizedAtMostOnce() async throws {
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = AtlasFixtures.uploadResponse(candidates: [])
        repository.recognitionsByMode[.escalate] = try AtlasRecognitionResponse(
            job: nil,
            candidates: [AtlasFixtures.candidate(id: "hi", level: "fine", label: "tabby")]
        )
        let (vm, _, _) = self.standUp(repository: repository)
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.escalate)
        await vm.requestRecognize(.escalate)

        #expect(repository.recognizeCalls == [.escalate])
        #expect(vm.lemma == "tabby")
    }

    @Test
    func anEmptyCachedResultIsNotTreatedAsFinal() async {
        // An upload whose inline recognition found nothing must stay retryable.
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = AtlasFixtures.uploadResponse(candidates: [])
        let (vm, _, _) = self.standUp(repository: repository)
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.primary)

        #expect(repository.recognizeCalls == [.primary])
    }

    @Test
    func anIncompleteGlossCacheIsRepairedExactlyOnce() async throws {
        // A ja interface learning 英文 expects a gloss. An older upload response
        // that has none gets one repair call — and, if the model still cannot
        // supply one, no more, or every later tap bills the user again.
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = try AtlasFixtures.uploadResponse(
            candidates: [AtlasFixtures.candidate(id: "c1", label: "cat", gloss: nil)]
        )
        repository.recognitionsByMode[.primary] = try AtlasRecognitionResponse(
            job: nil,
            candidates: [AtlasFixtures.candidate(id: "c1", label: "cat", gloss: nil)]
        )
        let (vm, _, _) = self.standUp(
            repository: repository,
            language: FakeLanguageContext(uiLang: "ja", learningDirection: .zhEn)
        )
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.primary)
        await vm.requestRecognize(.primary)
        await vm.requestRecognize(.primary)

        #expect(repository.recognizeCalls == [.primary])
    }

    @Test
    func aChineseInterfaceNeverSpendsACallRepairingAGlossItDoesNotUse() async throws {
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = try AtlasFixtures.uploadResponse(
            candidates: [AtlasFixtures.candidate(id: "c1", label: "cat", gloss: nil)]
        )
        let (vm, _, _) = self.standUp(
            repository: repository,
            language: FakeLanguageContext(uiLang: "zh-Hant", learningDirection: .zhJa)
        )
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.primary)

        #expect(repository.recognizeCalls.isEmpty)
        #expect(vm.secondField == .chineseName)
    }

    @Test
    func aSpentAllowanceOpensThePaywallRatherThanShowingARawError() async {
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = AtlasFixtures.uploadResponse(candidates: [])
        repository.recognizeError = APIError.paymentRequired(message: nil)
        let (vm, _, _) = self.standUp(repository: repository)
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.primary)

        #expect(vm.showPaywall)
        #expect(vm.errorMessage == nil)
    }

    @Test
    func aThrottleStaysAMessage() async {
        // 429 is transient — sending the user to the paywall would be a lie
        // about why the call failed.
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = AtlasFixtures.uploadResponse(candidates: [])
        repository.recognizeError = APIError.rateLimited(message: "慢一點")
        let (vm, _, _) = self.standUp(repository: repository)
        await vm.handlePicked(data: Data([0xFF]))

        await vm.requestRecognize(.primary)

        #expect(!vm.showPaywall)
        #expect(vm.errorMessage == "慢一點")
    }

    @Test
    func aFailedUploadReportsTheReasonTheIntakeWillPark() async {
        // The screen turns this into `.rejected(vm.errorMessage)`, so the frame
        // is parked by `ImageIntake` and 重試上傳 re-sends the same bytes. The VM
        // used to keep a second copy of them under `lastUploadData`.
        let repository = FakeAtlasAuthoring()
        repository.uploadError = AtlasFakeError.boom
        let (vm, _, _) = self.standUp(repository: repository)

        await vm.handlePicked(data: Data([0xFF, 0xD8]))

        #expect(vm.uploadedImage == nil)
        #expect(vm.errorMessage != nil)
    }

    @Test
    func submitHandsTheCaptureToTheQueueAndNothingElse() async {
        let repository = FakeAtlasAuthoring()
        repository.uploadResponse = AtlasFixtures.uploadResponse(candidates: [])
        let cards = FakeCardGenerating()
        let queue = AtlasCaptureQueue(
            cards: cards,
            journal: InMemoryCaptureJobJournal(),
            mutations: SpyAtlasMutationRefreshing(),
            doneLinger: .zero,
            celebrate: {}
        )
        let (vm, _, _) = self.standUp(repository: repository, queue: queue)
        await vm.handlePicked(data: Data([0xFF]))
        vm.lemma = "cat"
        vm.displayZhHant = "貓"

        vm.submit()

        // The injected queue receives it — the VM used to reach `.shared` here,
        // dropping the seam its own store arrived on.
        #expect(queue.jobs.count == 1)
        #expect(queue.jobs.first?.lemma == "cat")
        await queue.settle()
        #expect(cards.confirmedImageIds == ["img-1"])
    }

    @Test
    func capacityCountsWhatTheQueueIsStillMaking() async {
        let repository = FakeAtlasAuthoring()
        // One slot left on the server's snapshot.
        repository.entitlementValue = AtlasFixtures.entitlement(slots: 49, slotsLimit: 50)
        repository.uploadResponse = AtlasFixtures.uploadResponse(candidates: [])
        let cards = FakeCardGenerating()
        cards.confirmFailures = 1 // keep the job in flight long enough to observe
        let queue = AtlasCaptureQueue(
            cards: cards,
            journal: InMemoryCaptureJobJournal(),
            mutations: SpyAtlasMutationRefreshing(),
            doneLinger: .zero,
            celebrate: {}
        )
        let (vm, _, _) = self.standUp(repository: repository, queue: queue)
        await vm.prepareOnOpen()
        #expect(!vm.atCapacity)

        let running = queue.enqueue(
            imageId: "img-1",
            payload: AtlasFixtures.payload(),
            thumbnail: nil
        )
        // The last slot is claimed by a capture the server has not counted yet.
        #expect(vm.atCapacity)
        #expect(vm.capacity.blocker == .waitingOnQueue(1))
        await running.value
    }
}

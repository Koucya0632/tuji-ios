import Foundation
import Testing
@testable import Tuji

@MainActor
struct StudyChoicesTests {
    private func word(
        _ label: String,
        _ gloss: String = "",
        tier: Int = 1,
        language: TargetLanguage = .en,
        exclusions: [String] = []
    )
        -> StudyChoiceCandidate
    {
        StudyChoiceCandidate(
            wordId: label,
            label: label,
            language: language,
            gloss: gloss,
            category: nil,
            pos: nil,
            exclusions: exclusions,
            tier: tier,
            weight: 1
        )
    }

    private var target: StudyChoiceCandidate {
        self.word("washbasin", "洗手台")
    }

    private var candidates: [StudyChoiceCandidate] {
        ["spoon", "fork", "plate", "kettle", "towel", "mirror"].map { self.word($0) }
    }

    private func item() throws -> StudyQueueItem {
        let json = #"{"card":{"id":1},"word":{"id":"washbasin","word":"washbasin","chinese":"洗手台","imageUrl":"","pronunciation":"","category":"bath","targetLanguage":"en"},"choices":["wash basin","spoon","fork","washbasin"]}"#
        return try JSONDecoder().decode(StudyQueueItem.self, from: Data(json.utf8))
    }

    @Test
    func sharedContract() {
        for c in studyChoiceContractCases {
            let a = self.word(c.a, c.ag), b = self.word(c.b, c.bg)
            #expect(choicesConflict(a, b) == c.conflict, "\(c.name)")
            #expect(choicesConflict(b, a) == c.conflict, "\(c.name)")
        }
    }

    @Test
    func portableSamplingMatchesWebAndAndroid() {
        var rng = ChoiceRandom(state: 42)
        #expect((0..<3).map { _ in rng.next() * 4_294_967_296 } == [1_083_814_273, 378_494_188, 2_479_403_867])
        #expect(choiceHash("en:washbasin:0") == 3_207_774_618)
        #expect(assembleStudyChoices(target: self.target, candidates: self.candidates, seed: 42) == [
            "fork",
            "spoon",
            "kettle",
            "washbasin"
        ])
    }

    @Test
    func tiersAndPairwiseExclusions() {
        let choices = assembleStudyChoices(
            target: self.target,
            candidates: [self.word("spoon"), self.word("fork", tier: 2), self.word("kettle", tier: 3)],
            seed: 42
        )
        #expect(Set(choices) == Set(["washbasin", "spoon", "fork", "kettle"]))
        let input = [self.word("wash basin", "臉盆"), self.word("sofa"), self.word("couch")] + (0..<20)
            .map { self.word("term\($0)") }
        let pool = prepareChoiceCandidates(target: self.target, input: input)
        #expect(pool.count == 12)
        for (i, a) in pool.enumerated() {
            #expect(!choicesConflict(self.target, a))
            for b in pool.dropFirst(i + 1) {
                #expect(!choicesConflict(a, b))
            }
        }
    }

    @Test
    func sessionSnapshotSurvivesRefreshAndRotatesOnRetry() throws {
        var item = try self.item()
        #expect(item.choiceCandidates == nil)
        item.choiceCandidates = self.candidates
        let session = StudyChoiceSession(seed: 42)
        let first = session.choices(for: item, pool: [], session: .en, variant: 0)
        item.choiceCandidates = []
        #expect(session.choices(for: item, pool: [], session: .en, variant: 0) == first)
        item.choiceCandidates = self.candidates
        let retry = session.choices(for: item, pool: [], session: .en, variant: 1)
        #expect(retry.count(where: { !first.contains($0) }) >= 2)
        #expect(!retry.contains("wash basin"))
    }

    @Test
    func bilingualReserveCoverageAndCustomTargets() {
        for target in StudyChoiceData.reserve + [self.word("my object"), self.word("自分の物", language: .ja)] {
            let options = assembleStudyChoices(target: target, candidates: [], seed: 42)
            #expect(options.count == 4)
            #expect(Set(options.map(choiceKey)).count == 4)
            for label in options where label != target.label {
                #expect(StudyChoiceData.reserve.contains { $0.label == label && $0.language == target.language })
            }
        }
    }

    @Test
    func manySeedsVaryCombinationsAndPositions() throws {
        var sets: Set<String> = []
        var positions = [0, 0, 0, 0]
        for i in 0..<256 {
            let result = assembleStudyChoices(
                target: self.target,
                candidates: self.candidates,
                seed: choiceHash("round:\(i)")
            )
            try positions[#require(result.firstIndex(of: self.target.label))] += 1
            sets.insert(result.filter { $0 != self.target.label }.sorted().joined(separator: "|"))
        }
        #expect(sets.count > 10)
        #expect(positions.allSatisfy { $0 > 30 && $0 < 100 })
    }

    @Test
    func liveExclusionsSurviveReserveDuplicates() {
        let blocked = self.word("spoon", tier: 4, exclusions: ["wash basin"])
        for seed: UInt32 in 0..<32 {
            #expect(!assembleStudyChoices(target: self.target, candidates: [blocked], seed: seed).contains("spoon"))
        }
    }
}

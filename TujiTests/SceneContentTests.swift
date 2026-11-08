// Holds the bundled 場面 to scene-contract.md. The audio pipeline writes its
// script from the same files, so a scene that breaks the contract breaks both.

import Foundation
import Testing
@testable import Tuji

struct SceneContentTests {
    private func catalog() throws -> SceneCatalog {
        try SceneCatalog.load(bundle: .main)
    }

    private func allQuestions() throws -> [(PracticeScene, SceneQuestion)] {
        try self.catalog().scenes.flatMap { scene in scene.questions.map { (scene, $0) } }
    }

    @Test
    func everyListedSceneDecodesFromTheAppBundle() throws {
        let catalog = try self.catalog()
        #expect(catalog.scenes.map(\.id) == SceneCatalog.bundledIDs)
        #expect(catalog.scenes.allSatisfy { $0.schemaVersion == 1 })
        #expect(catalog.scenes.allSatisfy { $0.questions.count == 6 })
        #expect(SceneCatalog.bundled.scenes.count == SceneCatalog.bundledIDs.count)
    }

    @Test
    func everyQuestionHasOneFirstAndTwoReviewsOneOfThemFastWithAmbience() throws {
        for (_, question) in try self.allQuestions() {
            let firsts = question.phrasings.filter { $0.role == .first }
            let reviews = question.phrasings.filter { $0.role == .review }
            #expect(question.phrasings.count >= 3, "\(question.id.rawValue)")
            #expect(firsts.count == 1, "\(question.id.rawValue)")
            #expect(reviews.count >= 2, "\(question.id.rawValue)")
            #expect(reviews.contains { $0.isHardest }, "\(question.id.rawValue) needs a fast review with ambience")
        }
    }

    @Test
    func listeningPhrasingsAreSpokenAndScreenPhrasingsShowAScreen() throws {
        for (_, question) in try self.allQuestions() {
            for phrasing in question.phrasings {
                switch question.kind {
                case .listening:
                    #expect(phrasing.spoken != nil, "\(phrasing.id.rawValue)")
                    #expect(phrasing.screen == nil, "\(phrasing.id.rawValue)")
                case .screen:
                    #expect(phrasing.screen != nil, "\(phrasing.id.rawValue)")
                }
            }
        }
    }

    @Test
    func aPhrasingWithOnlySomeOfItsSpokenFieldsDoesNotDecode() {
        let json = Data("""
        {"id":"x.q.p1","role":"first","speaker":"clerk","text":"温めますか？","voice":null,
         "speed":"normal","ambience":false,"screen":null,"audio":"x.mp3"}
        """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Phrasing.self, from: json) }
    }

    @Test
    func anUnknownScreenDoesNotDecode() {
        let json = Data("""
        {"id":"x.q.p1","role":"first","speaker":"screen","text":null,"voice":null,
         "speed":"normal","ambience":false,"screen":"vending-machine","audio":null}
        """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Phrasing.self, from: json) }
    }

    @Test
    func idsAreUniqueAcrossScenesAndPrefixedByTheirParent() throws {
        var questionIds: Set<SceneQuestionID> = []
        var phrasingIds: Set<PhrasingID> = []
        for (scene, question) in try self.allQuestions() {
            #expect(question.id.rawValue.hasPrefix(scene.id.rawValue + "."), "\(question.id.rawValue)")
            #expect(questionIds.insert(question.id).inserted, "duplicate \(question.id.rawValue)")
            for phrasing in question.phrasings {
                #expect(phrasing.id.rawValue.hasPrefix(question.id.rawValue + "."), "\(phrasing.id.rawValue)")
                #expect(phrasingIds.insert(phrasing.id).inserted, "duplicate \(phrasing.id.rawValue)")
            }
        }
    }

    @Test
    func everyQuestionHasThreeOrFourChoicesWithExactlyOneCorrect() throws {
        for (_, question) in try self.allQuestions() {
            #expect((3...4).contains(question.choices.count), "\(question.id.rawValue)")
            #expect(question.choices.filter(\.correct).count == 1, "\(question.id.rawValue)")
            #expect(Set(question.choices.map(\.id)).count == question.choices.count, "\(question.id.rawValue)")
        }
    }

    @Test
    func everyScreenDrawsExactlyTheButtonsItsQuestionOffers() throws {
        for (_, question) in try self.allQuestions() where question.kind == .screen {
            let choiceIds = Set(question.choices.map(\.id))
            for phrasing in question.phrasings {
                let screen = try #require(phrasing.screen)
                #expect(Set(screen.buttons.map(\.choiceId)) == choiceIds, "\(phrasing.id.rawValue)")
            }
        }
    }

    @Test
    func everyLocalizedTextIsFilledInAllThreeLanguages() throws {
        for scene in try self.catalog().scenes {
            var texts = [scene.title, scene.summary]
            for question in scene.questions {
                texts.append(question.goal)
                texts.append(question.explanation)
                texts.append(contentsOf: question.choices.map(\.text))
                #expect(!question.response.ja.isEmpty, "\(question.id.rawValue)")
            }
            for text in texts {
                #expect(text.all.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(text)")
            }
        }
    }

    @Test
    func reviewLinesAreReadByADifferentVoiceThanFirstPractice() throws {
        for (_, question) in try self.allQuestions() {
            guard let firstVoice = question.firstPhrasing?.spoken?.voice else { continue }
            for review in question.phrasings where review.role == .review && review.speaker == .clerk {
                #expect(review.spoken?.voice != firstVoice, "\(review.id.rawValue)")
            }
        }
    }

    @Test
    func registerAnnouncementsUseOneVoice() throws {
        let voices = try self.allQuestions()
            .flatMap { $0.1.phrasings }
            .filter { $0.speaker == .register }
            .compactMap { $0.spoken?.voice }
        #expect(Set(voices).count <= 1)
    }

    /// The audio arrives in a later step. Until the folder has any clip in it the
    /// screens read the lines with on-device synthesis; from the first clip on,
    /// every file the scenes name must be there.
    @Test
    func everyReferencedClipExistsOnceTheAudioFolderHasAny() throws {
        let audioDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tuji/Resources/Scenes/audio", isDirectory: true)
        let present = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: audioDir.path))?
                .filter { $0.hasSuffix(".mp3") } ?? []
        )
        guard !present.isEmpty else { return }
        for (_, question) in try self.allQuestions() {
            let referenced = question.phrasings.compactMap { $0.spoken?.audio }
                + [question.response.clip?.audio].compactMap { $0 }
            for file in referenced {
                #expect(present.contains(file), "missing clip \(file)")
            }
        }
    }

    @Test
    func aJapaneseInterfaceReadsTheEnglishCopy() {
        let text = LocalizedText(zhHant: "加熱", zhHans: "加热", en: "Heat")
        #expect(text.resolved(.zhHant) == "加熱")
        #expect(text.resolved(.zhHans) == "加热")
        #expect(text.resolved(.en) == "Heat")
        #expect(text.resolved(.ja) == "Heat")
    }
}

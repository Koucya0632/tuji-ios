// Holds the bundled 場面 to scene-contract.md. The audio pipeline writes its
// script from the same files, so a scene that breaks the contract breaks both.

import Foundation
import Testing
import UIKit
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
        let ids = try SceneCatalog.ids(bundle: .main)
        #expect(!ids.isEmpty)
        #expect(catalog.scenes.map(\.id) == ids)
        #expect(catalog.scenes.allSatisfy { $0.schemaVersion == 2 })
        #expect(catalog.scenes.allSatisfy { (5...7).contains($0.questions.count) })
        #expect(SceneCatalog.bundled.scenes.count == ids.count)
    }

    /// A scene file left out of `index.json` would ship and never show.
    @Test
    func everySceneFileIsListedInTheIndex() throws {
        let scenesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tuji/Resources/Scenes", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: scenesDir.path)
            .filter { $0.hasSuffix(".json") && $0 != "index.json" }
        let listed = try SceneCatalog.ids(bundle: .main).map { $0.rawValue + ".json" }
        #expect(Set(files) == Set(listed))
        #expect(Set(listed).count == listed.count, "an id is listed twice")
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

    /// A schema 1 draft named its screen; schema 2 writes it out.
    @Test
    func aScreenGivenByNameDoesNotDecode() {
        let json = Data("""
        {"id":"x.q.p1","role":"first","speaker":"screen","text":null,"voice":null,
         "speed":"normal","ambience":false,"screen":"payment-select","audio":null}
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
                let buttonIds = screen.buttons.map(\.choiceId)
                #expect(buttonIds.count == choiceIds.count, "\(phrasing.id.rawValue): one button per choice")
                #expect(Set(buttonIds) == choiceIds, "\(phrasing.id.rawValue)")
                #expect(!screen.heading.isEmpty, "\(phrasing.id.rawValue)")
                #expect(screen.detail?.isEmpty != true, "\(phrasing.id.rawValue)")
                #expect(screen.buttons.allSatisfy { !$0.ja.isEmpty }, "\(phrasing.id.rawValue)")
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
            for review in question.phrasings where review.role == .review && [.clerk, .staff].contains(review.speaker) {
                #expect(review.spoken?.voice != firstVoice, "\(review.id.rawValue)")
            }
        }
    }

    @Test
    func registerAnnouncementsUseOneVoice() throws {
        let voices = try self.allQuestions()
            .flatMap(\.1.phrasings)
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
                + [question.response.clip?.audio].compactMap(\.self)
            for file in referenced {
                #expect(present.contains(file), "missing clip \(file)")
            }
        }
    }

    /// The audio script names each clip after what it voices.
    @Test
    func clipsAreNamedAfterTheirPhrasingOrQuestion() throws {
        for (_, question) in try self.allQuestions() {
            for phrasing in question.phrasings {
                if let audio = phrasing.spoken?.audio {
                    #expect(audio == phrasing.id.rawValue + ".mp3", "\(phrasing.id.rawValue): \(audio)")
                }
            }
            if let audio = question.response.clip?.audio {
                #expect(audio == question.id.rawValue + ".response.mp3", "\(question.id.rawValue): \(audio)")
            }
        }
    }

    /// Only official 圖鑑 ids: `scripts/scenes/check-word-ids.mjs` checks they exist.
    @Test
    func wordIdsAreOfficialKebabCaseIdsListedOnce() throws {
        let kebab = /[a-z0-9]+(-[a-z0-9]+)*/
        for (_, question) in try self.allQuestions() {
            #expect(Set(question.wordIds).count == question.wordIds.count, "\(question.id.rawValue)")
            for id in question.wordIds {
                #expect(id.wholeMatch(of: kebab) != nil, "\(question.id.rawValue): \(id)")
            }
        }
    }

    /// The content lists the right answer first more than half the time; on
    /// screen it must not land in one slot that often.
    @Test
    func theRightAnswerIsSpreadAcrossThePositionsAListeningQuestionShows() throws {
        var positions: [Int: Int] = [:]
        var shown = 0
        for (_, question) in try self.allQuestions() where question.kind == .listening {
            for phrasing in question.phrasings {
                let order = question.choices(for: phrasing.id)
                #expect(order == question.choices(for: phrasing.id), "\(phrasing.id.rawValue): stable")
                #expect(Set(order.map(\.id)) == Set(question.choices.map(\.id)), "\(phrasing.id.rawValue)")
                let position = order.firstIndex { $0.correct }
                #expect(position != nil, "\(phrasing.id.rawValue)")
                positions[position ?? -1, default: 0] += 1
                shown += 1
            }
        }
        for slot in 0..<3 {
            let share = Double(positions[slot] ?? 0) / Double(shown)
            #expect((0.2...0.45).contains(share), "slot \(slot): \(positions[slot] ?? 0) of \(shown)")
        }
    }

    // MARK: - Stage

    @Test
    func everySpokenReplyHasItsClip() throws {
        for scene in try self.catalog().scenes {
            for step in scene.stage?.steps.values.map(\.self) ?? [] {
                for reply in step.replies ?? [] where reply.isSpoken {
                    #expect(SceneCatalog.audioURL(reply.clip) != nil, "\(reply.ja) has no \(reply.clip)")
                }
            }
        }
    }

    @Test
    func aStagedSceneStagesEveryQuestionAndNothingElse() throws {
        for scene in try self.catalog().scenes {
            guard let stage = scene.stage else { continue }
            #expect(Set(stage.steps.keys) == Set(scene.questions.map(\.id.rawValue)), "\(scene.id.rawValue)")
        }
    }

    /// Every 問句 is met on some trip, a trip names only this scene's 問句 once
    /// each, and the trip first practice takes comes first.
    @Test
    func everyStagedQuestionIsOnATripAndTheFirstTripIsTheDefault() throws {
        for scene in try self.catalog().scenes {
            guard let stage = scene.stage else { continue }
            let ids = Set(scene.questions.map(\.id))
            #expect(!stage.routes.isEmpty, "\(scene.id.rawValue)")
            #expect(stage.routes.first?.isOptional == false, "\(scene.id.rawValue): first trip must be the default")
            #expect(Set(stage.routes.map(\.id)).count == stage.routes.count, "\(scene.id.rawValue)")
            #expect(Set(stage.routes.flatMap(\.questions)) == ids, "\(scene.id.rawValue): a 問句 no trip meets")
            for route in stage.routes {
                #expect(Set(route.questions).count == route.questions.count, "\(route.id) repeats a 問句")
                #expect(route.questions.allSatisfy(ids.contains), "\(route.id)")
                #expect(
                    (route.title.all + route.intent.all + route.enter.all).allSatisfy { !$0.isEmpty },
                    "\(route.id)"
                )
            }
        }
    }

    @Test
    func aStagedListeningQuestionOffersRepliesAndAScreenQuestionNone() throws {
        for (scene, question) in try self.allQuestions() {
            guard let step = scene.stageStep(question.id) else { continue }
            let replies = step.replies ?? []
            switch question.kind {
            case .listening:
                #expect((2...4).contains(replies.count), "\(question.id.rawValue)")
                #expect(replies.contains { $0.fits }, "\(question.id.rawValue): one reply must fit")
                #expect(Set(replies.map(\.id)).count == replies.count, "\(question.id.rawValue)")
                #expect(step.machine == nil, "\(question.id.rawValue)")
                for reply in replies {
                    #expect(!reply.ja.isEmpty)
                    #expect((reply.meaning.all + reply.result.all).allSatisfy { !$0.isEmpty }, "\(reply.id)")
                }
            case .screen:
                #expect(replies.isEmpty, "\(question.id.rawValue)")
            }
        }
    }

    @Test
    func everyStageImageIsInTheAssetCatalog() throws {
        for scene in try self.catalog().scenes {
            for step in scene.stage?.steps.values.map(\.self) ?? [] {
                let names = [step.background] + (step.props ?? []) + (step.replies ?? []).flatMap { $0.show ?? [] }
                for name in names {
                    #expect(UIImage(named: name) != nil, "\(scene.id.rawValue): missing image \(name)")
                }
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

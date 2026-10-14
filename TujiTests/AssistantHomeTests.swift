import Foundation
import Testing
@testable import Tuji

@MainActor
private final class HomeAssistantAPI: AssistantAsking {
    private(set) var offers = 0
    private(set) var requests: [AssistantAskPayload] = []

    func assistantOffer() async throws -> AssistantOffer {
        self.offers += 1
        return AssistantOffer(minPoints: 1, maxPoints: 5, available: 100)
    }

    func askAssistant(_ payload: AssistantAskPayload) async throws -> AssistantAnswer {
        self.requests.append(payload)
        return AssistantAnswer(
            answer: "answer",
            inScope: true,
            wordIds: [],
            charged: 1,
            available: 99,
            minPoints: 1,
            maxPoints: 5
        )
    }
}

@MainActor
struct AssistantHomeTests {
    private func conversation(api: HomeAssistantAPI) -> AssistantChatModel {
        let dictionary = AssistantDictionary([AssistantFixture.word("cat", word: "cat")])
        let language = FakeLanguageContext()
        return AssistantChatModel(responder: TieredAssistantResponder(
            local: LocalAssistantResponder(dictionary: dictionary),
            model: api, dictionary: dictionary, language: language
        ))
    }

    @Test
    func homeOffersOnlyExistingCapabilities() {
        #expect(AssistantHomeFeature.allCases.map(\.route) == [
            .assistantChat(entry: .intent(.lookupPrompt)),
            .assistantChat(entry: .conversation),
            .assistantStory
        ])
    }

    @Test
    func aQuestionIsTrimmedAndBlankDraftsCannotNavigate() {
        #expect(AssistantChatEntry.question(" \n ") == nil)
        #expect(AssistantChatEntry.question(" cat\n") == .text("cat"))
        #expect(AssistantChatEntry.conversation.focusesComposer)
        #expect(AssistantChatEntry.intent(.lookupPrompt).focusesComposer)
        #expect(!AssistantChatEntry.text("cat").focusesComposer)
        #expect(!AssistantChatEntry.intent(.lookup(query: "cat")).focusesComposer)
    }

    @Test
    func enteringAndUsingEveryShortcutNeverCallsPaidAI() async {
        for feature in AssistantHomeFeature.allCases {
            guard case let .assistantChat(entry) = feature.route else { continue }
            let api = HomeAssistantAPI()
            let model = self.conversation(api: api)
            model.start(entry)
            await model.settle()
            #expect(api.requests.isEmpty)
            #expect(api.offers == 0)
        }
    }

    @Test
    func returningToAConversationDoesNotResendOrResetIt() async {
        let api = HomeAssistantAPI()
        let model = self.conversation(api: api)
        #expect(model.start(.text(" cat ")))
        await model.settle()
        #expect(model.messages.count == 3)
        #expect(model.messages[1].body == .user("cat"))
        model.choose(.lookupPrompt)
        await model.settle()
        let retained = model.messages
        #expect(!model.start(.text("cat")))
        await model.settle()
        #expect(model.messages == retained)
        #expect(api.requests.isEmpty)
        #expect(api.offers == 0)
    }

    @Test
    func aTypedQuestionOnlyOffersAIPaymentNeedsTheExplicitChoice() async {
        let api = HomeAssistantAPI()
        let model = self.conversation(api: api)
        model.start(.text("why is this a language question"))
        await model.settle()
        #expect(api.requests.isEmpty)
        #expect(api.offers == 1)
        let choice = model.suggestions.first
        #expect(choice == .askModel(question: "why is this a language question"))
        if let choice { model.choose(choice) }
        await model.settle()
        #expect(api.requests.count == 1)
        #expect(!model.start(.text("why is this a language question")))
        await model.settle()
        #expect(api.requests.count == 1)
    }

    @Test
    func evenAPaidIntentCannotAuthorizeSpendingWhenUsedAsAnEntry() async {
        let api = HomeAssistantAPI()
        let model = self.conversation(api: api)
        model.start(.intent(.askModel(question: "why is this a language question")))
        await model.settle()
        #expect(api.requests.isEmpty)
        #expect(api.offers == 1)
        #expect(model.suggestions.first == .askModel(question: "why is this a language question"))
    }
}

struct MascotAnimationTests {
    @Test
    func blinkingClosesAndOpensInOrder() {
        let times = [-0.01, 0, 0.054, 0.055, 0.139, 0.14, 0.219, 0.22]
        #expect(times.map { MascotAnimationFrame(elapsed: 0, blinkElapsed: $0, wagElapsed: nil).eyes }
            == [.open, .half, .half, .closed, .closed, .half, .half, .open])
    }

    @Test
    func breathingAndTailReturnToRest() {
        let rest = MascotAnimationFrame(elapsed: 0, blinkElapsed: nil, wagElapsed: 0)
        #expect(rest.breath == 0)
        #expect(rest.wag == 0)
        let peak = MascotAnimationFrame(elapsed: 1.85, blinkElapsed: nil, wagElapsed: 0.12)
        #expect(abs(peak.breath - 1) < 0.0001)
        #expect(abs(peak.wag) > 0.5)
        let finished = MascotAnimationFrame(elapsed: 3.7, blinkElapsed: nil, wagElapsed: 1.65)
        #expect(abs(finished.breath) < 0.0001)
        #expect(finished.wag == 0)
    }

    @Test
    func hiddenBackgroundAndReducedMotionAllRenderTheRestingPose() {
        let frame = MascotAnimationFrame(elapsed: 1.85, blinkElapsed: 0.09, wagElapsed: 0.12, enabled: false)
        #expect(frame.breath == 0)
        #expect(frame.wag == 0)
        #expect(frame.eyes == .open)
    }
}

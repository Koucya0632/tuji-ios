// 拍照新增's paid recognition, walked through `CreditCaptureModel`'s own
// interface with fakes at its seams.
//
// This is the path a user's points move on, and before the seams existed the
// one test that constructed the model ran it against the live singletons — so
// the rules below (one upload per photo, never accept a price the user did not
// see, resend an uncertain accept under the same key, drop an answer that
// arrives for another account) were verified by nothing.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct CreditCaptureModelTests {
    private let user = UUID()

    /// Who is signed in, as a box a test can change mid-request.
    private final class Session {
        var user: UUID?
        init(_ user: UUID?) {
            self.user = user
        }
    }

    private struct Stand {
        let model: CreditCaptureModel
        let queue: AtlasCaptureQueue
        let api: FakeCreditCaptureAPI
        let journal: InMemoryPendingAcceptJournal
        let session: Session
        let credits: FakeCreditConfirming
        let cards: FakeCardGenerating
        let naps: Naps
    }

    /// Records what `watch()` asked to sleep, and never actually waits.
    private final class Naps {
        var asked: [Duration] = []
    }

    private func stand(
        api: FakeCreditCaptureAPI = FakeCreditCaptureAPI(),
        journal: InMemoryPendingAcceptJournal? = nil,
        language: FakeLanguageContext = FakeLanguageContext(uiLang: "zh-Hant", learningDirection: .zhEn),
        owned: [String] = [],
        resume: String? = nil,
        setAside: InMemorySetAsideJournal = InMemorySetAsideJournal()
    )
        -> Stand
    {
        let session = Session(self.user)
        let journal = journal ?? InMemoryPendingAcceptJournal()
        let credits = FakeCreditConfirming()
        let cards = FakeCardGenerating()
        let naps = Naps()
        let queue = AtlasCaptureQueue(
            cards: cards, credits: credits, journal: InMemoryCaptureJobJournal(),
            mutations: SpyAtlasMutationRefreshing(), doneLinger: .zero,
            enrichmentPoll: .milliseconds(1), enrichmentDeadline: .seconds(60), celebrate: {}
        )
        let model = CreditCaptureModel(
            resume: resume, api: api, queue: queue, account: { session.user }, pendingJournal: journal,
            setAside: setAside, language: language,
            ownedLemmas: { owned }, cards: cards, mutations: SpyAtlasMutationRefreshing(),
            sleep: { naps.asked.append($0) }
        )
        return Stand(
            model: model,
            queue: queue,
            api: api,
            journal: journal,
            session: session,
            credits: credits,
            cards: cards,
            naps: naps
        )
    }

    /// Loaded, with a photo chosen: the state 開始識別 is pressed in.
    private func ready(_ s: Stand) async {
        await s.model.load()
        s.model.setPhoto(Data([0xFF, 0xD8, 0xFF]))
    }

    // MARK: - Reopening a result

    @Test
    func 繼續確認OpensOnThePhotoThatWasAskedForNotTheNewestOneWaiting() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [
            CreditFixtures.operation(id: "newer", state: "committed", image: "img-2"),
            CreditFixtures.operation(id: "older", state: "committed", image: "img-1")
        ]

        let asked = self.stand(api: api, resume: "img-1")
        await asked.model.load()
        #expect(asked.model.operation?.id == "older")
        guard case .result = asked.model.panel else {
            Issue.record("expected the result panel, got \(asked.model.panel)")
            return
        }

        // The camera button asks for nothing in particular and still gets the newest.
        let camera = self.stand(api: api)
        await camera.model.load()
        #expect(camera.model.operation?.id == "newer")
    }

    @Test
    func aPhotoWithNothingToReopenDoesNotOpenOnSomeoneElsesResult() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(id: "other", state: "committed", image: "img-2")]
        let s = self.stand(api: api, resume: "img-1")

        await s.model.load()

        #expect(s.model.operation == nil)
    }

    @Test
    func aResultWhosePhotoWasDeletedIsPassedOverForTheNextOneWaiting() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [
            CreditFixtures.operation(id: "orphan", state: "committed", image: "gone"),
            CreditFixtures.operation(id: "older", state: "committed", image: "img-1")
        ]
        api.imageErrors["gone"] = APIError.notFound
        let s = self.stand(api: api)

        await s.model.load()

        #expect(s.model.operation?.id == "older")
        #expect(s.model.image?.id == "img-1")
    }

    @Test
    func 換一張PutsTheResultAsideSoTheNextVisitOpensOnTheOneBehindIt() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [
            CreditFixtures.operation(id: "newer", state: "committed", image: "img-2"),
            CreditFixtures.operation(id: "older", state: "committed", image: "img-1")
        ]
        let aside = InMemorySetAsideJournal()
        let first = self.stand(api: api, setAside: aside)
        await first.model.load()
        #expect(first.model.operation?.id == "newer")

        first.model.retake()
        await first.model.load()
        #expect(first.model.operation?.id == "older")

        first.model.retake()
        let next = self.stand(api: api, setAside: aside)
        await next.model.load()
        #expect(next.model.operation == nil)
    }

    @Test
    func 繼續確認StillOpensAResultThatWasSetAside() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(id: "waiting", state: "committed", image: "img-1")]
        let aside = InMemorySetAsideJournal()
        let camera = self.stand(api: api, setAside: aside)
        await camera.model.load()
        camera.model.retake()

        let detail = self.stand(api: api, resume: "img-1", setAside: aside)
        await detail.model.load()

        #expect(detail.model.operation?.id == "waiting")
    }

    @Test
    func aResultNobodySetAsideStillReopens() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(id: "waiting", state: "committed", image: "img-1")]
        let aside = InMemorySetAsideJournal()
        let first = self.stand(api: api, setAside: aside)
        await first.model.load()

        let next = self.stand(api: api, setAside: aside)
        await next.model.load()

        #expect(next.model.operation?.id == "waiting")
    }

    @Test
    func whenTheOnlyResultWaitingHasNoPhotoTheSheetOpensOnChoosingOne() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(id: "orphan", state: "committed", image: "gone")]
        api.imageErrors["gone"] = APIError.notFound
        let s = self.stand(api: api)

        await s.model.load()

        #expect(s.model.operation == nil)
        #expect(s.model.message == nil)
        guard case .source = s.model.panel else {
            Issue.record("expected the source panel, got \(s.model.panel)")
            return
        }
    }

    @Test
    func aPhotoThatCouldNotBeFetchedIsNotMistakenForADeletedOne() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(id: "waiting", state: "committed", image: "img-1")]
        api.imageErrors["img-1"] = APIError.transport(URLError(.notConnectedToInternet))
        let s = self.stand(api: api)

        await s.model.load()

        // Offline is not gone: the paid result stays reachable, just without its photo.
        #expect(s.model.operation?.id == "waiting")
        #expect(s.model.image == nil)
        #expect(s.model.message == nil)
    }

    // MARK: - Starting a recognition

    @Test
    func 開始識別UploadsQuotesAndAcceptsWhenThePriceIsTheOneOnScreen() async {
        let s = self.stand()
        await self.ready(s)

        await s.model.start(language: .en)

        #expect(s.api.uploads == 1)
        #expect(s.api.quotes.count == 1)
        #expect(s.api.accepts.map(\.quoteId) == ["quote-1"])
        #expect(s.model.operation?.id == "op-1")
        // Answered, so nothing is left to resend.
        #expect(s.model.pending == nil)
        #expect(s.journal.stored.isEmpty)
        guard case .recognizing = s.model.panel else {
            Issue.record("expected the recognizing panel, got \(s.model.panel)")
            return
        }
        #expect(s.model.step == 2)
    }

    @Test
    func aPriceTheUserDidNotSeeIsNeverAcceptedOnTheirBehalf() async {
        let api = FakeCreditCaptureAPI()
        api.quotePoints = 150 // the screen says 100
        let s = self.stand(api: api)
        await self.ready(s)

        await s.model.start(language: .en)

        #expect(s.api.accepts.isEmpty)
        guard case let .priceChanged(quote) = s.model.panel else {
            Issue.record("expected the price-changed panel, got \(s.model.panel)")
            return
        }
        #expect(quote.points == 150)

        // Saying yes accepts that same quote; it is not re-priced behind them.
        await s.model.accept()
        #expect(s.api.accepts.map(\.quoteId) == ["quote-1"])
        #expect(s.api.quotes.count == 1)
    }

    @Test
    func theSamePhotoIsUploadedOnceHoweverManyTimesItIsQuoted() async {
        let api = FakeCreditCaptureAPI()
        api.quotePoints = 150
        let s = self.stand(api: api)
        await self.ready(s)

        await s.model.start(language: .en)
        s.model.cancelQuote()
        await s.model.start(language: .en)

        #expect(s.api.uploads == 1)
        #expect(s.api.quotes.count == 2)
    }

    @Test
    func aPaidQuoteSaysWhichInterfaceItWasMadeOnAndLeavesTheRestToTheServer() async {
        // The gloss language used to be worked out here — at one point inside a
        // View — and the server took the client's word for it.
        for ui in UILanguage.allCases {
            let s = self.stand(language: FakeLanguageContext(uiLang: ui.rawValue, learningDirection: .zhEn))
            await self.ready(s)
            await s.model.start(language: .ja)
            #expect(s.api.quotes.first?.uiLanguage == ui)
            #expect(s.api.quotes.first?.target == .ja)
        }
    }

    // MARK: - An accept whose answer never arrived

    @Test
    func anUnansweredAcceptIsKeptAndResentUnderTheSameKey() async {
        let api = FakeCreditCaptureAPI()
        api.acceptResult = .failure(AtlasFakeError.boom) // timeout: charged or not, nobody knows
        let s = self.stand(api: api)
        await self.ready(s)

        await s.model.start(language: .en)

        let sent = s.api.accepts.first
        #expect(s.model.pending == sent)
        #expect(s.journal.stored.values.first == sent)

        api.acceptResult = .success(CreditFixtures.operation(state: "reserved"))
        await s.model.accept()

        // A new key here would be a second charge for the same photo.
        #expect(s.api.accepts.count == 2)
        #expect(s.api.accepts[1] == sent)
        #expect(s.model.pending == nil)
        #expect(s.journal.stored.isEmpty)
    }

    @Test
    func anExplicitRejectionClearsTheAcceptSoANewQuoteCanBeMade() async {
        for reason in CreditCaptureModel.acceptRejections {
            let api = FakeCreditCaptureAPI()
            api.acceptResult = .failure(APIError.conflict(reason: reason, message: nil))
            let s = self.stand(api: api)
            await self.ready(s)

            await s.model.start(language: .en)

            #expect(s.model.pending == nil, "\(reason)")
            #expect(s.journal.stored.isEmpty, "\(reason)")
            #expect(s.model.message != nil, "\(reason)")
        }
    }

    @Test
    func aRelaunchFindsTheUnansweredAcceptAndOffersToResendIt() async {
        let left = PendingAccept(quoteId: "quote-9", key: "key-9")
        let s = self.stand(journal: InMemoryPendingAcceptJournal(left, account: self.user))

        await s.model.load()

        #expect(s.model.pending == left)
        guard case .unansweredAccept = s.model.panel else {
            Issue.record("expected the unanswered-accept panel, got \(s.model.panel)")
            return
        }
        await s.model.accept()
        #expect(s.api.accepts == [left])
    }

    // MARK: - Following a run

    @Test
    func watchLooksEarlyThenEveryTwoSecondsUntilTheRunEnds() async {
        let api = FakeCreditCaptureAPI()
        api.polls = [
            .success(CreditFixtures.operation(state: "running")),
            .success(CreditFixtures.operation(state: "running")),
            .success(CreditFixtures.operation(state: "committed", candidates: [CreditFixtures.keyboard]))
        ]
        let s = self.stand(api: api)
        await self.ready(s)
        await s.model.start(language: .en)

        await s.model.watch()

        #expect(s.naps.asked == [.seconds(1), .seconds(2), .seconds(2)])
        #expect(s.api.polled == 3)
        #expect(s.model.operation?.status == .committed)
        guard case .result = s.model.panel else {
            Issue.record("expected the result panel, got \(s.model.panel)")
            return
        }
        // A settled run is not asked about again.
        await s.model.watch()
        #expect(s.api.polled == 3)
    }

    @Test
    func oneDroppedPollIsNotWorthABannerButThreeInARowAre() async {
        let api = FakeCreditCaptureAPI()
        api.polls = Array(repeating: .failure(AtlasFakeError.boom), count: 3)
            + [.success(CreditFixtures.operation(state: "running"))]
        let s = self.stand(api: api)
        await self.ready(s)
        await s.model.start(language: .en)

        await s.model.poll()
        await s.model.poll()
        #expect(s.model.message == nil)
        await s.model.poll()
        #expect(s.model.message != nil)
        // The next answer lifts the banner the polling raised.
        await s.model.poll()
        #expect(s.model.message == nil)
    }

    @Test
    func aRunThatAnswersIsNotAConnectionFailureWhenOnlyTheBalanceMisses() async {
        let api = FakeCreditCaptureAPI()
        api.polls = Array(repeating: .failure(AtlasFakeError.boom), count: 3)
            + [.success(CreditFixtures.operation(state: "committed", candidates: [CreditFixtures.keyboard]))]
        let s = self.stand(api: api)
        await self.ready(s)
        await s.model.start(language: .en)

        await s.model.poll()
        await s.model.poll()
        await s.model.poll()
        #expect(s.model.message != nil)
        // The run ends on a poll whose balance read fails. Polling stops here, so a
        // banner left up now would sit over the result with nothing to lift it.
        api.walletError = AtlasFakeError.boom
        await s.model.poll()
        #expect(s.model.message == nil)
        guard case .result = s.model.panel else {
            Issue.record("expected the result panel, got \(s.model.panel)")
            return
        }
    }

    @Test
    func anAnswerThatArrivesForAnotherAccountIsDropped() async {
        let api = FakeCreditCaptureAPI()
        let s = self.stand(api: api)
        await self.ready(s)
        // The user signs out — or switches account — while the accept is in the air.
        api.duringAccept = { s.session.user = UUID() }

        await s.model.start(language: .en)

        #expect(s.api.accepts.count == 1)
        #expect(s.model.operation == nil)
    }

    @Test
    func onlyARunThatHasNotStartedCanBeCancelled() async {
        let s = self.stand()
        await self.ready(s)
        await s.model.start(language: .en)
        #expect(s.model.canCancelOperation)

        await s.model.cancelOperation()

        #expect(s.model.operation?.status == .released)
        #expect(!s.model.canCancelOperation)
        guard case .released = s.model.panel else {
            Issue.record("expected the released panel, got \(s.model.panel)")
            return
        }
    }

    // MARK: - 高精度

    @Test
    func anUpgradeKeepsTheLanguageTheRunWasPaidForAndAsksForTheTopUpPrice() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(
            state: "committed",
            target: "ja",
            candidates: [CreditFixtures.keyboard]
        )]
        let s = self.stand(api: api)
        await s.model.load() // reopens on the result nobody picked from
        #expect(s.model.canUpgrade)

        // The learning language was switched to English since.
        await s.model.upgrade(language: .en)

        #expect(s.api.uploads == 0)
        #expect(s.api.quotes.first?.mode == .precision)
        #expect(s.api.quotes.first?.target == .ja)
        #expect(s.api.accepts.count == 1)
    }

    @Test
    func aRunOf高精度AlreadyPaidForIsASwitchNotASecondCharge() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [
            CreditFixtures.operation(id: "p", state: "committed", feature: "atlas.recognize.precision"),
            CreditFixtures.operation(id: "q", state: "committed")
        ]
        let s = self.stand(api: api)
        await s.model.load()

        #expect(!s.model.canUpgrade)
        s.model.show(.primary)
        #expect(s.model.operation?.id == "q")
        s.model.show(.precision)
        #expect(s.model.operation?.id == "p")
        #expect(s.api.quotes.isEmpty)
    }

    // MARK: - The card

    /// A model sitting on a delivered result, in the given interface language.
    private func delivered(ui: String, target: String = "en", correctionField: String? = nil) async -> Stand {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(
            state: "committed", target: target,
            candidates: [CreditCandidate(id: "c1", level: "primary", label: "keyboard", zhHant: "鍵盤", gloss: "キーボード")],
            correctionField: correctionField
        )]
        let s = self.stand(api: api, language: FakeLanguageContext(uiLang: ui, learningDirection: .zhEn))
        await s.model.load()
        return s
    }

    @Test
    func confirmHandsTheTrimmedNamesTo生成佇列AndClosesTheForm() async throws {
        let s = await self.delivered(ui: "zh-Hant")
        let candidate = try #require(s.model.operation?.result?.candidates.first)
        s.model.form.select(candidate)
        s.model.form.lemma = "  laptop \n"
        s.model.form.displayZhHant = " 筆電 "

        #expect(s.model.confirm())
        await s.queue.settle()

        #expect(s.credits.confirmed == [CreditConfirmRequest(
            operationId: "op-1", candidateId: "c1", lemma: "laptop", displayZhHant: "筆電", displayGloss: nil
        )])
        // The sheet is about to close; nothing of this capture is left on it.
        #expect(s.model.operation == nil)
    }

    @Test
    func aRenameOnAFormWithoutTheChineseFieldSendsNoChineseName() async throws {
        // 英文介面學英文: the form shows one field, so 鍵盤 could not be corrected.
        let s = await self.delivered(ui: "en")
        #expect(s.model.secondField == .hidden)
        let candidate = try #require(s.model.operation?.result?.candidates.first)
        #expect(s.model.candidateMeaning(candidate) == nil)
        s.model.form.select(candidate)
        s.model.form.lemma = "laptop"

        #expect(s.model.confirm())
        await s.queue.settle()

        #expect(s.credits.confirmed.first?.displayZhHant == nil)
        #expect(s.credits.confirmed.first?.displayGloss == nil)
    }

    @Test
    func aCrossLanguageRunEditsAndSendsItsGloss() async throws {
        let s = await self.delivered(ui: "ja")
        #expect(s.model.secondField == .gloss)
        let candidate = try #require(s.model.operation?.result?.candidates.first)
        #expect(s.model.candidateMeaning(candidate) == "キーボード")
        s.model.form.select(candidate)
        s.model.form.displayGloss = " 鍵盤 "

        #expect(s.model.confirm())
        await s.queue.settle()

        #expect(s.credits.confirmed.first?.displayGloss == "鍵盤")
        // Not renamed, so the candidate's Chinese name still describes the card.
        #expect(s.credits.confirmed.first?.displayZhHant == "鍵盤")
    }

    @Test
    func theFormTheServerDeclaredForTheRunWinsOverTheSettingsOfTheMoment() async {
        // Quoted on a Japanese interface; the user has since switched to Chinese.
        let s = await self.delivered(ui: "zh-Hant", correctionField: "gloss")
        #expect(s.model.secondField == .gloss)
        // A value this build does not know falls back to the grid.
        let unknown = await self.delivered(ui: "zh-Hant", correctionField: "something-new")
        #expect(unknown.model.secondField == .chineseName)
    }

    @Test
    func aNameTheAccountAlreadyHasIsWarnedAboutNotRefused() async {
        let api = FakeCreditCaptureAPI()
        api.operationsValue = [CreditFixtures.operation(state: "committed", candidates: [CreditFixtures.keyboard])]
        let s = self.stand(api: api, owned: ["Keyboard "])
        await s.model.load()
        s.model.form.select(CreditFixtures.keyboard)

        #expect(s.model.duplicateLemmaWarning != nil)
        #expect(s.model.canConfirm)
        s.model.form.lemma = "laptop"
        #expect(s.model.duplicateLemmaWarning == nil)
    }

    @Test
    func aSavedCardWhoseReviewCardsDidNotSyncIsRetriedWithoutConfirmingAgain() async {
        let api = FakeCreditCaptureAPI()
        // In flight, so `load` reopens on it; the poll then finds its card made.
        api.operationsValue = [CreditFixtures.operation(state: "running")]
        api.polls = [.success(CreditFixtures.operation(state: "committed", card: "item-7"))]
        let s = self.stand(api: api)
        await s.model.load()
        await s.model.poll()
        guard case .cardUnsynced = s.model.panel else {
            Issue.record("expected the unsynced panel, got \(s.model.panel)")
            return
        }

        #expect(await s.model.syncCards())

        #expect(s.cards.generatedItemIds == ["item-7"])
        #expect(s.cards.reconciles == 1)
        #expect(s.credits.confirmed.isEmpty)
    }
}

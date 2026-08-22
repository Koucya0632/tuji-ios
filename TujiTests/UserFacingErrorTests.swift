// Pins what a reader is allowed to see when something fails.
//
// The rule these tests protect was learned the hard way: during the 2026-08-19
// Supabase egress restriction, every auth call came back with a JSON body whose
// `message` was a billing notice addressed to the project owner, and the app
// put it on the onboarding screen — in English, to a zh-Hant reader, as the
// first thing a new user saw.
//
// Assertions here are about *provenance*, not copy: whether a foreign string
// can reach the screen. They deliberately never assert a localized sentence —
// CI runs in English and local runs in zh-Hant.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct UserFacingErrorTests {
    /// The exact body Supabase served while the project was restricted.
    private static let supabaseRestriction = """
    Service for this project is restricted due to the following violations: \
    exceed_cached_egress_quota, exceed_egress_quota. The project owner must \
    upgrade their plan or remove spend caps to restore service.
    """

    private struct ForeignError: LocalizedError {
        let errorDescription: String?
    }

    /// The regression itself. A third party's error text is not ours to show.
    @Test
    func aForeignErrorsOwnWordsNeverReachTheReader() {
        let message = tujiUserMessage(for: ForeignError(errorDescription: Self.supabaseRestriction))
        #expect(!message.contains("exceed_cached_egress_quota"))
        #expect(!message.contains("spend caps"))
        #expect(message != Self.supabaseRestriction)
        #expect(!message.isEmpty)
    }

    /// A 5xx body is a stack trace or an English infrastructure string. 402 and
    /// 429 are different — see `serverCopyIsKeptForTheCasesWeAuthored`.
    @Test
    func aServerBodyIsNotShown() {
        let body = "Error: connect ECONNREFUSED 10.0.0.3:5432\n    at TCPConnectWrap"
        let message = tujiUserMessage(for: APIError.server(status: 500, body: body))
        #expect(!message.contains("ECONNREFUSED"))
        #expect(!message.contains("TCPConnectWrap"))
    }

    /// …but the body still has to reach the log, or the outage becomes
    /// undiagnosable from the client side.
    @Test
    func theServerBodySurvivesForLogging() {
        let diagnostic = APIError.server(status: 500, body: "ECONNREFUSED").diagnostic
        #expect(diagnostic.contains("ECONNREFUSED"))
        #expect(diagnostic.contains("500"))
    }

    /// 402 and 429 carry product copy *we* wrote in zh-Hant (the atlas daily-AI
    /// cap), so those two arms do forward the server's message on purpose. This
    /// pins that the deliberate exception still holds — it is the reason the
    /// rule had to be stated rather than applied blanket.
    @Test
    func serverCopyIsKeptForTheCasesWeAuthored() {
        let ours = "今天的 AI 辨識次數用完了"
        #expect(tujiUserMessage(for: APIError.paymentRequired(message: ours)) == ours)
        #expect(tujiUserMessage(for: APIError.rateLimited(message: ours)) == ours)
    }

    /// Offline is the most common failure and already had good copy; the new
    /// boundary must not have flattened it into the generic line.
    @Test
    func offlineKeepsItsOwnExplanation() {
        let offline = tujiUserMessage(for: URLError(.notConnectedToInternet))
        let generic = tujiUserMessage(for: ForeignError(errorDescription: "boom"))
        #expect(offline != generic)
        #expect(!offline.isEmpty)
    }

    /// A screen with better words for its own context can supply them.
    @Test
    func aCallerCanSupplyItsOwnFallback() {
        let mine = "這張圖片沒能上傳"
        #expect(tujiUserMessage(for: ForeignError(errorDescription: "boom"), fallback: mine) == mine)
        // But a fallback must not override copy we actually own.
        let ours = "今天的 AI 辨識次數用完了"
        #expect(tujiUserMessage(for: APIError.paymentRequired(message: ours), fallback: mine) == ours)
    }

    /// A cancelled task is not a failure and must not be dressed up as one.
    @Test
    func cancellationIsNotAnError() {
        #expect(tujiUserMessage(for: CancellationError(), fallback: "x") == "x")
        #expect(tujiUserMessage(for: URLError(.cancelled), fallback: "x") == "x")
    }
}

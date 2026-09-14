import Testing
@testable import Tuji

/// See `TokenReplacement`: a refused token is replaced once, however many
/// requests were refused with it.
struct TokenReplacementTests {
    @Test
    func aRefusedTokenIsRefreshedEvenIfItIsTheOneTheSessionHolds() {
        // The defect: the device believed the refused token was still good, so
        // the retry was handed the same token and failed the same way.
        #expect(TokenReplacement.decide(current: "a", rejected: "a") == .refresh)
    }

    @Test
    func aTokenAnotherRetryAlreadyReplacedIsUsedNotRefreshedAgain() {
        #expect(TokenReplacement.decide(current: "b", rejected: "a") == .useCurrent)
    }

    @Test
    func noTokenInTheSessionMeansRefreshing() {
        #expect(TokenReplacement.decide(current: nil, rejected: "a") == .refresh)
        #expect(TokenReplacement.decide(current: nil, rejected: nil) == .refresh)
    }

    @Test
    func aRequestRefusedWithoutATokenTakesWhatTheSessionNowHolds() {
        #expect(TokenReplacement.decide(current: "b", rejected: nil) == .useCurrent)
    }
}

// Pins the whole flight rule, once.
//
// It was written three times — `WordsStore`, `CategoriesStore`, `SettingsStore`
// — and asserted three times in overlapping halves: `CatalogStoreLoadingTests`
// pins `categoriesDiscardLateObsoleteContext` with no words counterpart, and
// `wordsCancelledFlightCannotPublishIntoSameContextReplacement` with no
// categories counterpart. Three implementations, three partial descriptions.
//
// The stores keep their own suites: those assert what a landed flight *means*
// for that store, which is the store's business. These assert the flight.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct LoadFlightsTests {
    /// A gate a fetch can be held at, so a test can interleave requests.
    private final class Gate {
        private var resume: (() -> Void)?
        private var opened = false

        func wait() async {
            if self.opened { return }
            await withCheckedContinuation { continuation in
                self.resume = { continuation.resume() }
            }
        }

        func open() {
            self.opened = true
            self.resume?()
            self.resume = nil
        }
    }

    @Test
    func aResultPublishesWhenNothingElseHappened() async {
        let flights = LoadFlights<String>()
        var published: [String] = []

        await flights.run("a", fetch: { "A" }, publish: { value, _ in published.append(value) })

        #expect(published == ["A"])
    }

    /// Two callers asking for the same context share one request. This is the
    /// half all three suites did assert.
    @Test
    func twoCallersForOneKeyShareOneFetch() async {
        let flights = LoadFlights<String>()
        let gate = Gate()
        var fetches = 0
        var published: [String] = []

        let started = Gate()
        async let first: Void = flights.run(
            "a",
            fetch: {
                fetches += 1
                started.open()
                await gate.wait()
                return "A"
            },
            publish: { value, _ in published.append(value) }
        )
        // The first flight must have registered before the second asks, and a
        // yield only makes that likely — these suites run in parallel on one
        // actor, so "likely" is how a test passes alone and fails in the suite.
        await started.wait()
        async let second: Void = flights.run(
            "a",
            fetch: {
                fetches += 1
                return "A2"
            },
            publish: { value, _ in published.append(value) }
        )
        gate.open()
        _ = await (first, second)

        #expect(fetches == 1)
        #expect(published == ["A"])
    }

    /// The rule with the highest cost when it is missing: a slow answer to an
    /// abandoned question must not land. A reader who switches language twice
    /// must not see the first language's catalogue on the third screen.
    @Test
    func anAnswerToAnAbandonedKeyDoesNotPublish() async {
        let flights = LoadFlights<String>()
        let gate = Gate()
        var published: [String] = []

        let started = Gate()
        async let slow: Void = flights.run(
            "a",
            fetch: {
                started.open()
                await gate.wait()
                return "A"
            },
            publish: { value, _ in published.append(value) }
        )
        await started.wait()
        await flights.run("b", fetch: { "B" }, publish: { value, _ in published.append(value) })
        gate.open()
        await slow

        #expect(published == ["B"], "the abandoned key's answer must not land")
    }

    /// `isLoading` follows the *latest requested* key, not the number of
    /// flights: a request nobody is waiting for is not this store loading.
    @Test
    func loadingFollowsTheLatestRequestNotTheFlightCount() async {
        let flights = LoadFlights<String>()
        let gate = Gate()

        #expect(!flights.isLoading)

        let started = Gate()
        async let slow: Void = flights.run(
            "a",
            fetch: {
                started.open()
                await gate.wait()
            },
            publish: { _, _ in }
        )
        await started.wait()
        #expect(flights.isLoading)

        // Ask for something else; "a" is still in the air but no longer awaited.
        await flights.run("b", fetch: {}, publish: { _, _ in })
        #expect(!flights.isLoading, "a flight for an abandoned key is not loading")

        gate.open()
        await slow
    }

    /// A publish that suspends has to re-ask, because the world moves while it
    /// awaits. 設定 is the caller: it saves a migration back mid-landing and
    /// must not write `lastError` into a context that is no longer current.
    @Test
    func aSuspendingPublishCanSeeThatItWentStale() async {
        let flights = LoadFlights<String>()
        // Two gates rather than a yield: whether the landing has begun is
        // exactly what this test needs to be sure of, and a yield only makes it
        // likely. `reachedPublish` is opened by the landing, `release` by us.
        let reachedPublish = Gate()
        let release = Gate()
        var currentAtStart: Bool?
        var currentAfterAwait: Bool?

        async let first: Void = flights.run(
            "a",
            fetch: { "A" },
            publish: { _, stillCurrent in
                currentAtStart = stillCurrent()
                reachedPublish.open()
                await release.wait()
                currentAfterAwait = stillCurrent()
            }
        )
        await reachedPublish.wait()
        // Somebody asks for another context while the landing is suspended.
        await flights.run("b", fetch: { "B" }, publish: { _, _ in })
        release.open()
        await first

        #expect(currentAtStart == true)
        #expect(currentAfterAwait == false)
    }

    @Test
    func resetForgetsTheCurrentKeySoNothingMayLand() async {
        let flights = LoadFlights<String>()
        let gate = Gate()
        var published: [String] = []

        let started = Gate()
        async let slow: Void = flights.run(
            "a",
            fetch: {
                started.open()
                await gate.wait()
                return "A"
            },
            publish: { value, _ in published.append(value) }
        )
        await started.wait()
        flights.reset()
        gate.open()
        await slow

        #expect(published.isEmpty)
        #expect(!flights.isLoading)
    }

    /// 設定's first-run path: the answer arrived by another route, so a load
    /// already on its way must not land on top of the choices just made.
    @Test
    func adoptDropsWhatIsInTheAirAndKeepsTheKeyCurrent() async {
        let flights = LoadFlights<String>()
        let gate = Gate()
        var published: [String] = []

        let started = Gate()
        async let slow: Void = flights.run(
            "a",
            fetch: {
                started.open()
                await gate.wait()
                return "A"
            },
            publish: { value, _ in published.append(value) }
        )
        await started.wait()
        flights.adopt("a")
        gate.open()
        await slow

        #expect(published.isEmpty, "the in-flight answer must not overwrite the adopted one")
        #expect(!flights.isLoading)
    }

    /// After a reset the desk is clear, not poisoned: the next request is a
    /// fresh question and must be allowed to land.
    @Test
    func aRequestAfterAResetStillLands() async {
        let flights = LoadFlights<String>()
        var published: [String] = []

        flights.reset()
        await flights.run("a", fetch: { "A" }, publish: { value, _ in published.append(value) })

        #expect(published == ["A"])
    }
}

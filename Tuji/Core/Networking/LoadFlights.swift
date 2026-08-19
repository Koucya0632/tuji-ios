// One load in the air per context, and the rule about which result may land.
//
// `WordsStore`, `CategoriesStore` and `SettingsStore` each kept a private copy
// of this. Not "similar" — `refreshLoadingState()` is byte-identical in all
// three, and `load(for:)` differs between the first two only in a parameter
// name. The three test suites that cover it assert overlapping subsets:
// categories pins `discardLateObsoleteContext` and words does not; words pins
// `cancelledFlightCannotPublishIntoSameContextReplacement` and categories does
// not. Three implementations, three partial descriptions of one rule.
//
// **This is not the staleness rule.** CONTEXT.md's "Staleness is per-store and
// not uniform" is correct and load-bearing — `MasteryStore` uses `loadIfNeeded`
// with no TTL for a documented reason, and that argument must stay where it is.
// What repeats is *how one request runs*, not *when another is due*. The two get
// called "store boilerplate" together and should not be.
//
// The rules, which were subtle enough to be worth writing carefully once:
//
//   • Two callers asking for the same context share one request.
//   • Only the latest *requested* context may publish. A user who switches
//     language twice must not see the first answer land on the third screen.
//   • A flight that was superseded — same context, new request — drops its
//     result rather than overwriting the newer one.
//   • `isLoading` follows the latest request, not the count of flights.

import Foundation

/// The loads in flight, keyed by whatever identifies a request.
///
/// `Key` is the store's own context type: `CatalogContext` for the catalogue
/// stores, `{ userID }` for settings.
@MainActor
final class LoadFlights<Key: Hashable> {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var inFlight: [Key: Flight] = [:]

    /// The context most recently asked for. Publishing is measured against this
    /// rather than against the key being fetched, which is what stops a slow
    /// answer to an abandoned question from landing.
    private(set) var latestRequested: Key?

    /// True while the *latest requested* context is still in the air. A flight
    /// for an abandoned context is not this store loading; it is a request no
    /// one is waiting for.
    var isLoading: Bool {
        guard let latestRequested else { return false }
        return self.inFlight[latestRequested] != nil
    }

    /// Whether `key` currently has a request in the air.
    func isInFlight(_ key: Key) -> Bool {
        self.inFlight[key] != nil
    }

    /// Answers "am I still the flight whose result may land?", for a `publish`
    /// that suspends. Handed to `publish` rather than derived by it: a caller
    /// that awaits mid-landing has to re-ask, and re-asking is the module's
    /// question, not the store's.
    typealias StillCurrent = @MainActor () -> Bool

    /// Fetches for `key`, then publishes — unless the answer went stale first.
    ///
    /// Joining an existing flight awaits it and returns; the work is not
    /// started twice and `publish` runs once, inside the flight that owns it.
    func run<Value>(
        _ key: Key,
        fetch: @escaping @MainActor () async -> Value,
        publish: @escaping @MainActor (Value, StillCurrent) async -> Void
    ) async {
        self.latestRequested = key

        if let existing = self.inFlight[key] {
            await existing.task.value
            return
        }

        let id = UUID()
        let task = Task { [weak self] in
            let value = await fetch()
            guard let self else { return }
            // Two ways to go stale: the reader moved on to another context, or
            // this very context was re-requested and a newer flight owns it now.
            let stillCurrent: StillCurrent = { [weak self] in
                guard let self else { return false }
                return self.latestRequested == key && self.inFlight[key]?.id == id
            }
            guard stillCurrent() else { return }
            await publish(value, stillCurrent)
        }
        self.inFlight[key] = Flight(id: id, task: task)
        await task.value

        // Only the flight that is still the current one clears the slot — a
        // superseded flight finishing later must not evict its replacement.
        if self.inFlight[key]?.id == id {
            self.inFlight[key] = nil
        }
    }

    /// Cancels everything in the air. The tasks check `latestRequested` before
    /// publishing anyway, so this is about not doing the remaining work.
    func cancelAll() {
        for flight in self.inFlight.values {
            flight.task.cancel()
        }
        self.inFlight.removeAll()
    }

    /// `cancelAll()` plus forgetting what was asked for — a store invalidating
    /// has no current context, so nothing may publish into it.
    func reset() {
        self.cancelAll()
        self.latestRequested = nil
    }

    /// The answer for `key` arrived by another route, so nothing in the air may
    /// overwrite it. 設定 does this when first-run setup POSTs the settings
    /// itself: a `load()` already on its way would otherwise land on top of the
    /// choices the user just made.
    func adopt(_ key: Key) {
        self.cancelAll()
        self.latestRequested = key
    }
}

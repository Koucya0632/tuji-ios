import Foundation
import Observation
import os

/// 補充中 — the tail of the 罐頭點數 capture. Confirming a candidate makes the card
/// at once, but its reading, definitions and examples arrive a few seconds later
/// from a server-side fulfillment the card itself says nothing about. This watch
/// keeps the item ids whose fulfillment is still open, so the 我做的 grid can say
/// so, and reloads the learning stores when one lands so the new fields show.
///
/// It is fed from the operations the capture screen already reads (confirm and
/// load); it does not fetch the operation list on its own.
@MainActor
@Observable
final class CreditEnrichmentWatch {
    static let shared = CreditEnrichmentWatch()

    /// Atlas item ids (bare UUIDs) still being filled in.
    private(set) var enrichingItemIds: Set<String> = []

    @ObservationIgnored private var operationByItem: [String: String] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let fetch: @MainActor (String) async throws -> CreditOperation
    @ObservationIgnored private let mutations: AtlasMutationRefreshing
    @ObservationIgnored private let interval: Duration
    /// A fulfillment that fails retries two minutes later, up to three times. Past
    /// this the label stops promising anything; the fields still land whenever the
    /// server finishes, on the next reload.
    @ObservationIgnored private let giveUpAfter: Duration
    @ObservationIgnored private let log = Logger(subsystem: "app.tuji.ios", category: "credit-enrichment")

    init(
        fetch: @escaping @MainActor (String) async throws -> CreditOperation = {
            try await APIClient.shared.get(.aiOperation(id: $0))
        },
        mutations: AtlasMutationRefreshing = LiveAtlasMutationRefresher(),
        interval: Duration = .seconds(3),
        giveUpAfter: Duration = .seconds(150)
    ) {
        self.fetch = fetch
        self.mutations = mutations
        self.interval = interval
        self.giveUpAfter = giveUpAfter
    }

    /// The returned task is the poll loop, for a test to await; production ignores it.
    @discardableResult
    func track(_ operations: [CreditOperation]) -> Task<Void, Never>? {
        for operation in operations {
            guard let itemId = operation.confirmedItemId else { continue }
            if operation.isEnriching {
                self.operationByItem[itemId] = operation.id
                self.enrichingItemIds.insert(itemId)
            } else {
                self.operationByItem[itemId] = nil
                self.enrichingItemIds.remove(itemId)
            }
        }
        guard !self.operationByItem.isEmpty, self.loop == nil else { return self.loop }
        self.loop = Task { await self.run() }
        return self.loop
    }

    func reset() {
        self.loop?.cancel()
        self.loop = nil
        self.operationByItem = [:]
        self.enrichingItemIds = []
    }

    private func run() async {
        defer { self.loop = nil }
        let deadline = ContinuousClock.now + self.giveUpAfter
        while !self.operationByItem.isEmpty, !Task.isCancelled {
            do { try await Task.sleep(for: self.interval) } catch { return }
            var landed = false
            for (itemId, operationId) in self.operationByItem {
                do {
                    let operation = try await self.fetch(operationId)
                    guard !operation.isEnriching else { continue }
                    landed = landed || operation.fulfillmentState == "completed"
                    self.operationByItem[itemId] = nil
                    self.enrichingItemIds.remove(itemId)
                } catch {
                    self.log.error("enrichment poll failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if landed { await self.mutations.refresh(after: .cardEnriched) }
            if ContinuousClock.now >= deadline {
                self.operationByItem = [:]
                self.enrichingItemIds = []
            }
        }
    }
}

extension CreditOperation {
    /// The card exists and its server-side fill-in has not finished.
    var isEnriching: Bool {
        self.confirmedItemId != nil && ["pending", "running", "reconciling"].contains(self.fulfillmentState)
    }
}

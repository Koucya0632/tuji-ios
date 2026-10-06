// Pins the 補充中 label's lifetime: on while the server is still filling in a
// confirmed card, off once it lands (and the learning stores reload so the new
// fields show), and never stuck on a fulfillment that stops answering.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct CreditEnrichmentWatchTests {
    private func operation(_ id: String, item: String?, fulfillment: String) -> CreditOperation {
        CreditOperation(
            id: id,
            state: "committed",
            feature: "atlas.recognize.primary",
            targetLanguage: "ja",
            imageId: "image-\(id)",
            points: 100,
            confirmedItemId: item,
            fulfillmentState: fulfillment,
            result: nil
        )
    }

    @Test
    func aCardIsEnrichingUntilItsFulfillmentLandsThenTheStoresReload() async {
        var answers = ["pending", "completed"]
        let spy = SpyAtlasMutationRefreshing()
        let watch = CreditEnrichmentWatch(
            fetch: { id in self.operation(id, item: "item-1", fulfillment: answers.removeFirst()) },
            mutations: spy,
            interval: .milliseconds(1)
        )
        let loop = watch.track([self.operation("op-1", item: "item-1", fulfillment: "pending")])
        #expect(watch.enrichingItemIds == ["item-1"])

        await loop?.value
        #expect(watch.enrichingItemIds.isEmpty)
        #expect(spy.reported == [.cardEnriched])
    }

    @Test
    func finishedOrUnconfirmedOperationsNeverShowTheLabel() {
        let watch = CreditEnrichmentWatch(fetch: { _ in throw URLError(.notConnectedToInternet) })
        let loop = watch.track([
            self.operation("a", item: "item-a", fulfillment: "completed"),
            self.operation("b", item: nil, fulfillment: "unclaimed")
        ])
        #expect(loop == nil)
        #expect(watch.enrichingItemIds.isEmpty)
    }

    @Test
    func aFulfillmentThatStopsAnsweringDoesNotKeepTheLabelForever() async {
        let spy = SpyAtlasMutationRefreshing()
        let watch = CreditEnrichmentWatch(
            fetch: { _ in throw URLError(.timedOut) },
            mutations: spy,
            interval: .milliseconds(1),
            giveUpAfter: .milliseconds(20)
        )
        let loop = watch.track([self.operation("op-1", item: "item-1", fulfillment: "running")])
        await loop?.value
        #expect(watch.enrichingItemIds.isEmpty)
        #expect(spy.reported.isEmpty)
    }
}

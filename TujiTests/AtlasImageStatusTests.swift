// Pins the capture-pipeline status enum. The mapping used to be a `private`
// free function inside AtlasManageView.swift — unreachable even from
// `@testable import`, so all seven labels and the unknown-status passthrough
// went unverified.

import Foundation
import Testing
@testable import Tuji

@MainActor
struct AtlasImageStatusTests {
    @Test
    func everyWireStatusParses() {
        let wire = [
            "uploaded", "processing", "needs_review",
            "confirmed", "cards_ready", "failed", "deleted"
        ]
        #expect(wire.compactMap(AtlasImageStatus.init(rawValue:)).count == wire.count)
        #expect(AtlasImageStatus.allCases.map(\.rawValue).sorted() == wire.sorted())
    }

    @Test
    func everyStatusHasANonEmptyLabelAndTheyAreDistinct() {
        let labels = AtlasImageStatus.allCases.map(\.label)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
    }

    @Test
    func onlyPostConfirmStatusesImplyAnItem() {
        #expect(AtlasImageStatus.confirmed.impliesConfirmedItem)
        #expect(AtlasImageStatus.cardsReady.impliesConfirmedItem)

        #expect(!AtlasImageStatus.uploaded.impliesConfirmedItem)
        #expect(!AtlasImageStatus.processing.impliesConfirmedItem)
        #expect(!AtlasImageStatus.needsReview.impliesConfirmedItem)
        #expect(!AtlasImageStatus.failed.impliesConfirmedItem)
        #expect(!AtlasImageStatus.deleted.impliesConfirmedItem)
    }

    /// A status this build doesn't know must still be visible rather than blank.
    @Test
    func anUnknownStatusFallsThroughRaw() {
        let image = AtlasFixtures.image("i1", status: "quantum_superposition")

        #expect(image.statusKind == nil)
        #expect(image.statusLabel == "quantum_superposition")
    }

    @Test
    func aPreItemStatusUsesItsOwnLabelAsTheRowTitle() {
        for status in AtlasImageStatus.allCases where !status.impliesConfirmedItem {
            let image = AtlasFixtures.image("i1", status: status.rawValue)
            #expect(image.placeholderTitle == status.label)
        }
    }

    /// The contradiction: an image whose pipeline finished but whose item hasn't
    /// reached this device read 「未完成」 while the chip beside it read 「已完成」.
    @Test
    func aFinishedImageWithNoItemDoesNotClaimToBeUnfinished() {
        for status in AtlasImageStatus.allCases where status.impliesConfirmedItem {
            let image = AtlasFixtures.image("i1", status: status.rawValue)
            #expect(image.placeholderTitle != status.label)
            #expect(image.placeholderTitle != tujiLocalized("未完成"))
        }
    }
}

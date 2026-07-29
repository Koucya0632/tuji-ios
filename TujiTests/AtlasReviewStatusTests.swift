// Pins the two removal states apart.
//
// 'withdrawn' (the author's own 取消公開) and 'takedown' (moderation removing
// the item) look identical on screen — the item is gone from the wall — and
// mean opposite things. If they ever collapse into one value, one of two bugs
// follows: removed content walks back onto the wall, or an author who changed
// their mind can never publish that card again.

import Foundation
import Testing
@testable import Tuji

struct AtlasReviewStatusTests {
    @Test
    func withdrawnCanBePublishedAgainButTakedownCannot() {
        #expect(AtlasReviewStatus.withdrawn.canSubmit)
        #expect(AtlasReviewStatus.takedown.canSubmit == false)
    }

    @Test
    func onlyALivePublicItemOffersWithdrawal() {
        #expect(AtlasReviewStatus.approved.canWithdraw)
        for status: AtlasReviewStatus in [
            .draft, .pending, .pendingAuto, .pendingReview, .rejected, .takedown, .withdrawn
        ] {
            #expect(status.canWithdraw == false, "expected \(status.rawValue) not to offer withdrawal")
        }
    }

    /// In-flight submissions must not be re-submittable — the machine gate is
    /// already holding them.
    @Test
    func queuedStatesOfferNeitherAction() {
        for status: AtlasReviewStatus in [.pending, .pendingAuto, .pendingReview] {
            #expect(status.canSubmit == false)
            #expect(status.canWithdraw == false)
        }
    }

    @Test
    func withdrawnReadsAsTheAuthorsOwnDoing() {
        #expect(AtlasReviewStatus.withdrawn.label != AtlasReviewStatus.takedown.label)
    }

    /// The server sends raw strings; an unknown one must not silently decode as
    /// something publishable.
    @Test
    func statusDecodesFromTheServerSpelling() {
        #expect(AtlasReviewStatus(rawValue: "withdrawn") == .withdrawn)
        #expect(AtlasReviewStatus(rawValue: "pending_review") == .pendingReview)
        #expect(AtlasReviewStatus(rawValue: "nonsense") == nil)
    }
}

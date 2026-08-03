import SwiftUI
import Testing
import UIKit
@testable import Tuji

@MainActor
struct AtlasCollectionDetailLayoutTests {
    @Test
    func screenClaimsTheFullAvailableWidth() {
        let view = AtlasCollectionDetailView(slug: "layout-probe")
            .environment(AuthService.shared)
            .environment(CollectionBookmarkStore())
            .environment(CollectionIdentityStore())
            .environment(DeepLinkCoordinator.shared)
        let host = UIHostingController(rootView: view)

        let size = host.sizeThatFits(in: CGSize(width: 390, height: 800))

        #expect(abs(size.width - 390) < 0.5)
    }

    @Test
    func collectionEditLoadingScreenClaimsTheFullAvailableWidth() {
        let view = AtlasCollectionEditView(collectionId: "layout-probe")
            .environment(CommunityFeedRefresh())
            .environment(CollectionIdentityStore())
        let host = UIHostingController(rootView: view)

        let size = host.sizeThatFits(in: CGSize(width: 390, height: 800))

        #expect(abs(size.width - 390) < 0.5)
    }
}

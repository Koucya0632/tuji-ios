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
            .environment(DeepLinkCoordinator.shared)
        let host = UIHostingController(rootView: view)

        let size = host.sizeThatFits(in: CGSize(width: 390, height: 800))

        #expect(abs(size.width - 390) < 0.5)
    }
}

// Animated SwiftUI continuation of the native launch screen. The native
// LaunchLockupPeekStart asset is the exact first frame of TujiBrandLockup's
// entrance; after SwiftUI takes over, the portal opens and the cat peeks out.
// LaunchCoordinator keeps this surface visible for at least 600ms and, for a
// main-shell route, until the catalog attempt finishes. Reduce Motion resolves
// directly to the final lockup without playing the entrance.

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.tujiPaper
                .ignoresSafeArea()

            TujiBrandLockup(animateEntrance: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview { SplashView() }

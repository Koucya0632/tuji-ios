// Shown while AuthService is restoring session (~100–300ms typical).
//
// **No motion at all.** Under 850ms nobody needs to be told the app is loading;
// skeletons and progress bars exist for waits long enough to notice. The spinner
// that used to fade in here was answering a question no one had asked.
//
// The spec also puts this on ink, so the launch runs straight into Welcome's ink
// face without changing ground. Not yet: Welcome is still paper (its rework is
// D.11.3), and an ink splash handing over to a paper Welcome flips the ground
// under the user — worse than what is here now. Ink lands with Welcome.

import SwiftUI

struct SplashView: View {
    var body: some View {
        TujiBrandLockup()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.tujiPaper)
    }
}

#Preview { SplashView() }

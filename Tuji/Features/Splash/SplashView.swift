// Shown while AuthService is restoring session (~ 100-300ms typical).

import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: Space.s5) {
            Mascot(pose: .face, size: 88)

            HStack(spacing: 0) {
                Text("Tuji")
                Text(".").foregroundStyle(.tujiCoral)
            }
            .font(.tujiH1)
            .foregroundStyle(.tujiInk)

            ProgressView()
                .tint(.tujiTeal)
                .padding(.top, Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }
}

#Preview { SplashView() }

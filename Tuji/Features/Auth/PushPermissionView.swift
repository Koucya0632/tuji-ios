// Shown once after first sign-in. Whichever button the user taps, we
// mark `hasBeenPrompted` and let RootView swap to MainTabs.

import SwiftUI

struct PushPermissionView: View {
    @Environment(PushNotificationService.self) private var push
    let onDone: () -> Void

    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle().fill(.tujiTealSoft).frame(width: 120, height: 120)
                Image(systemName: "bell.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.tujiTeal)
            }

            Text("每天輕推你一下")
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .padding(.top, Space.s6)

            VStack(spacing: Space.s2) {
                Text("20:00 提醒你今天還沒學")
                Text("連勝快斷時提早告訴你")
            }
            .font(.tujiBodyLg)
            .foregroundStyle(.tujiInk2)
            .padding(.top, Space.s4)
            .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: Space.s3) {
                BBtn(
                    title: working ? "請求中..." : "好，開啟提醒",
                    bg: .tujiTeal,
                    fg: .white,
                    fullWidth: true,
                    icon: "bell.fill",
                    action: grant
                )
                .disabled(working)

                Button {
                    push.markPrompted()
                    onDone()
                } label: {
                    Text("現在不要")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.tujiInk3)
                        .padding(.vertical, Space.s3)
                }
                .disabled(working)
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }

    private func grant() {
        working = true
        Task {
            _ = await push.requestAuthorization()
            // requestAuthorization marks prompted internally
            working = false
            onDone()
        }
    }
}

#Preview {
    PushPermissionView(onDone: {})
        .environment(PushNotificationService.shared)
}

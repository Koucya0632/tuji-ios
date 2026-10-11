// 拍照新增的入口 (presented as a fullScreenCover from the tab bar's camera).
//
// There is one capture flow — 罐頭點數 (`CreditCaptureView`) — and this decides
// whether the account gets it. It used to be two screens in one file: the
// pre-credit flow lived here in full and the credit flow was an `if` at the top
// of its body, read off a singleton. The pre-credit flow is retired
// (docs/adr/0016): no account could reach it, and every rule of the correction
// form existed twice and had drifted.

import SwiftUI

/// What tapping the camera opens.
enum CaptureEntry: Equatable {
    /// A 罐頭點數 account: the capture flow.
    case capture
    /// Not a member. 自製圖鑑 is a membership feature, so the only useful thing
    /// to show is how to become one.
    case membership
    /// The entitlement has not arrived. Guessing would show a member the
    /// membership page, or a non-member a flow the server refuses.
    case resolving

    init(_ entitlement: AtlasEntitlement?) {
        guard let entitlement else {
            self = .resolving
            return
        }
        self = entitlement.billingMode == "credits" ? .capture : .membership
    }
}

struct AtlasCaptureView: View {
    /// A capture was handed to 生成佇列; the host shows 我做的, where its tile is.
    var onCardQueued: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let store: AtlasStore
    /// The entitlement was asked for and still did not arrive.
    @State private var unreachable = false

    init(store: AtlasStore = .shared, onCardQueued: @escaping () -> Void = {}) {
        self.store = store
        self.onCardQueued = onCardQueued
    }

    var body: some View {
        switch CaptureEntry(self.store.entitlement) {
        case .capture:
            CreditCaptureView(onCardQueued: self.onCardQueued)
        case .membership:
            PaywallView()
        case .resolving:
            TujiFormSheet(title: "拍照新增", closeDisabled: false, onClose: { self.dismiss() }, content: {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if self.unreachable {
                        Text("暫時無法連線，請重試同步。")
                            .font(.tujiBody)
                            .foregroundStyle(.tujiInk)
                        BBtn(title: "重試", fullWidth: true) {
                            Task { await self.resolve() }
                        }
                    } else {
                        TujiProgressBar(progress: nil)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            })
            .task { await self.resolve() }
        }
    }

    private func resolve() async {
        self.unreachable = false
        await self.store.refreshEntitlement()
        self.unreachable = self.store.entitlement == nil
    }
}

#Preview {
    AtlasCaptureView()
        .environment(AuthService.shared)
}

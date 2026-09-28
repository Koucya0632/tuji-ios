// 我 → 詞表. Absent under membership v1 and for guests; a lock for a
// non-member with nothing yet; otherwise the way in.

import SwiftUI

struct MeWordListsRow: View {
    @Environment(WordListsStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var showPaywall = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Always drawn, so the `.task` below runs — see `TaskAnchor`.
            TaskAnchor()
            if !self.auth.isGuest {
                switch self.store.browseEntry {
                case .hidden:
                    EmptyView()
                case .locked:
                    Button { self.showPaywall = true } label: { self.row(locked: true) }
                        .buttonStyle(.plain)
                case .open:
                    NavigationLink(value: WordListRoute.lists) { self.row(locked: false) }
                        .buttonStyle(.plain)
                }
            }
        }
        .task {
            guard !self.auth.isGuest else { return }
            await self.store.loadIfNeeded()
        }
        .sheet(isPresented: self.$showPaywall) { PaywallView() }
    }

    private func row(locked: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "list.bullet.rectangle")
                .font(.tujiIcon(18, weight: .semibold))
                .foregroundStyle(.tujiInk2)
            VStack(alignment: .leading, spacing: 2) {
                Text("詞表")
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                Text(locked ? "會員功能：把字整理成自己的詞表來背" : "\(self.store.lists.count) 張詞表")
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiInk3)
            }
            Spacer()
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.tujiIcon(12, weight: .semibold))
                .foregroundStyle(.tujiInk3)
        }
        .padding(Space.s3)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r0)
                .stroke(.tujiRule.opacity(0.2), lineWidth: 1)
        )
        .contentShape(.rect)
    }
}

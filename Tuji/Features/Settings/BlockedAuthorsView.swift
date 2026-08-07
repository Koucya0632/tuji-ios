// 已封鎖的人 — the only place a block can be undone.
//
// It has to exist and it has to be here: blocking someone removes them from
// every surface where you would otherwise meet them, so "go find them again and
// unblock" is not a route. Settings is where the account's own state lives.
//
// Deliberately just handles. Rendering the blocked author's nickname and avatar
// would put the face someone chose to stop seeing back on screen, in a list they
// opened to manage exactly that.

import SwiftUI

struct BlockedAuthorsView: View {
    @Environment(BlockStore.self) private var blocks
    @State private var working: String?

    private var handles: [String] {
        self.blocks.handles.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back)
            ScrollView {
                TujiScreenTitle("已封鎖的人")

                if self.handles.isEmpty {
                    Text("你還沒有封鎖任何人。")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.top, Space.s3)
                } else {
                    TujiSection(footer: "解除後，你會重新看到這個人公開的內容。") {
                        ForEach(self.handles, id: \.self) { handle in
                            TujiRow(
                                leading: {
                                    Text(verbatim: handle.uppercased())
                                        .font(.tujiMono)
                                        .foregroundStyle(.tujiInk)
                                },
                                trailing: {
                                    Button {
                                        self.unblock(handle)
                                    } label: {
                                        Text(self.working == handle ? "解除中…" : "解除封鎖")
                                            .font(.tujiLabel)
                                            .tracking(0.5)
                                            .foregroundStyle(.tujiTeal)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(self.working != nil)
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(.tujiPaper)
        .navigationTitle("已封鎖的人")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.blocks.loadIfNeeded()
        }
    }

    private func unblock(_ handle: String) {
        self.working = handle
        Task {
            await self.blocks.unblock(handle: handle)
            self.working = nil
        }
    }
}

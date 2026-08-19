// One 封鎖 flow — what the control says, what the prompt says, which way the
// write goes, and what happens after — shared by 物見詳情 and 作者主頁.
//
// 檢舉 was deduped into `ReportFlow` for exactly this reason, and the dedupe
// found a real defect while it was in there (two screens marked a report sent
// before awaiting it). 封鎖 sat beside it and stayed written twice, with the
// same 32-character detail line typed out in both files. The two had already
// drifted: 作者主頁 offers 解除封鎖, 物見詳情 only disables its button; 作者主頁
// puts both actions in a `Menu`, 物見詳情 stacks two plain buttons.
//
// Unlike `ReportFlow` this owns no write and no phase — `BlockStore` already
// holds the optimistic insert, the rollback on failure, and the lowercased key.
// An `@Observable` wrapper over a handle and a bool would be a module whose
// interface is as wide as its implementation. What is worth having one home for
// is the *copy* and the *branch*, so that is what the modifier takes.

import SwiftUI

/// What 封鎖 offers for one author right now, and what it should say.
///
/// The screens ask this question in three places each — the control's label,
/// the prompt's title, the prompt's detail — and answered it three times.
enum BlockAction: Equatable {
    case block
    case unblock

    init(isBlocked: Bool) {
        self = isBlocked ? .unblock : .block
    }

    /// The prompt's title.
    var title: LocalizedStringKey {
        switch self {
        case .block: "封鎖這位作者？"
        case .unblock: "解除封鎖？"
        }
    }

    /// The prompt's body. 封鎖 is reversible and does not touch what the reader
    /// already collected — saying so is the difference between a decision and a
    /// dead end.
    var detail: LocalizedStringKey {
        switch self {
        case .block: "你不會再看到這個人公開的內容。已經收進圖鑑的字不受影響，隨時可以解除。"
        case .unblock: "解除後你會重新看到這個人公開的內容。"
        }
    }

    /// The confirming button in the prompt.
    var confirmLabel: LocalizedStringKey {
        switch self {
        case .block: "封鎖"
        case .unblock: "解除封鎖"
        }
    }

    /// Blocking is destructive-flavoured; undoing it is not. Two properties
    /// rather than one because the prompt and the control that opens it take
    /// different role types — `TujiPromptButtonRole` and SwiftUI's `ButtonRole`.
    var confirmRole: TujiPromptButtonRole {
        switch self {
        case .block: .destructive
        case .unblock: .primary
        }
    }

    var controlRole: ButtonRole? {
        switch self {
        case .block: .destructive
        case .unblock: nil
        }
    }

    /// What the control that opens the prompt says.
    var controlLabel: LocalizedStringKey {
        switch self {
        case .block: "封鎖這位作者"
        case .unblock: "解除封鎖"
        }
    }
}

private struct BlockPromptModifier: ViewModifier {
    let handle: String?
    @Binding var isPresented: Bool
    let onBlocked: () -> Void

    @Environment(BlockStore.self) private var blocks

    private var action: BlockAction {
        BlockAction(isBlocked: self.blocks.isBlocked(self.handle))
    }

    func body(content: Content) -> some View {
        content.tujiPrompt(
            isPresented: self.$isPresented,
            style: .confirmation,
            title: self.action.title,
            detail: self.action.detail,
            primary: TujiPromptAction(self.action.confirmLabel, role: self.action.confirmRole) {
                // `TujiPrompt` nils its backing state before running the action,
                // so the handle is read into a local first — the trap CONTEXT.md
                // records. Here it matters twice: the action also outlives the
                // prompt through an `await`.
                guard let handle = self.handle else { return }
                let action = self.action
                Task {
                    switch action {
                    case .block:
                        if await self.blocks.block(handle: handle) {
                            // The screen is now showing content the reader just
                            // asked never to see again.
                            self.onBlocked()
                        }
                    case .unblock:
                        await self.blocks.unblock(handle: handle)
                    }
                }
            },
            secondary: TujiPromptAction("取消", role: .cancel) {}
        )
    }
}

extension View {
    /// Hosts the 封鎖/解除封鎖 confirmation. The screen keeps only the control that
    /// sets `isPresented`, and says what leaving looks like for it.
    ///
    /// `handle` is optional because both callers derive it — a nil handle (no
    /// author on the payload, or the viewer's own item) means there is nothing
    /// to block and the prompt is inert.
    func blockPrompt(
        handle: String?,
        isPresented: Binding<Bool>,
        onBlocked: @escaping () -> Void = {}
    )
        -> some View
    {
        self.modifier(BlockPromptModifier(
            handle: handle,
            isPresented: isPresented,
            onBlocked: onBlocked
        ))
    }
}

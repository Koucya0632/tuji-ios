// Pins which way 封鎖 goes, and how loudly.
//
// 檢舉 was deduped into `ReportFlow`; 封鎖 sat beside it and stayed written
// twice, and the two had already drifted — 作者主頁 offers 解除封鎖 where 物見詳情
// only disables its button. The question "is this a block or an unblock, and
// what does that button look like" was answered three times per screen (control
// label, prompt title, prompt detail), all inside `View` bodies.
//
// Asserted here as decisions, not sentences: CI runs in English and the copy is
// zh-Hant, so the tests name the branch and leave the wording to the catalogue.

import SwiftUI
import Testing
@testable import Tuji

struct BlockActionTests {
    @Test
    func anUnblockedAuthorIsOfferedABlockAndViceVersa() {
        #expect(BlockAction(isBlocked: false) == .block)
        #expect(BlockAction(isBlocked: true) == .unblock)
    }

    /// Blocking is destructive-flavoured; undoing it is not. The two screens
    /// disagreed on this — one made 解除封鎖 a plain row, the other never offered
    /// it at all.
    @Test
    func onlyBlockingReadsAsDestructive() {
        #expect(BlockAction.block.confirmRole == .destructive)
        #expect(BlockAction.unblock.confirmRole == .primary)
        #expect(BlockAction.block.controlRole == .destructive)
        #expect(BlockAction.unblock.controlRole == nil)
    }

    /// Four labels, and the two directions must not share one: a prompt whose
    /// title said 封鎖 while its button said 解除封鎖 is exactly the kind of thing
    /// two hand-written copies produce.
    @Test
    func theTwoDirectionsSayDifferentThings() {
        #expect(BlockAction.block.title != BlockAction.unblock.title)
        #expect(BlockAction.block.detail != BlockAction.unblock.detail)
        #expect(BlockAction.block.confirmLabel != BlockAction.unblock.confirmLabel)
        #expect(BlockAction.block.controlLabel != BlockAction.unblock.controlLabel)
    }
}

// The 生成卡片 tail of the capture pipeline — the exact four steps 生成佇列 runs
// once the user has confirmed a name, and nothing else.
//
// Carved off `AtlasStore` so the queue depends on the slice it drives rather
// than on the whole store, and so a test can run a job against an in-memory
// adapter. Until this existed the queue reached `AtlasStore.shared` statically
// at four call sites, which is why the durable half of the pipeline — the
// confirm checkpoint, the resume rule, retry — had no tests at all.
//
// Narrower than `AtlasAuthoring` on purpose: the queue discards the card list
// `createCards` returns and always reconciles `.full`, so neither the return
// value nor the scope belongs on this seam (see CONTEXT.md → role seams).

import Foundation

@MainActor
protocol AtlasCardGenerating {
    /// A plain INSERT server-side, and therefore **not idempotent**. The queue
    /// checkpoints the item this returns so a resumed run never calls it twice.
    func confirm(imageId: String, payload: AtlasConfirmPayload) async throws -> AtlasItem
    /// Idempotent — which is exactly what makes resuming from the checkpoint safe.
    func generateCards(forItem itemId: String) async throws
    /// Definition / synonyms / forms / etymology. Best-effort: the detail
    /// endpoint enriches lazily on open, so a failure here never fails the card.
    func enrich(itemId: String) async throws
    /// The reconciling read a finished capture needs before its cards are true.
    func reconcile() async
}

extension AtlasStore: AtlasCardGenerating {
    /// The created cards are the server's receipt, not state anything reads.
    func generateCards(forItem itemId: String) async throws {
        _ = try await self.createCards(itemId: itemId)
    }

    /// `.full`, never `.incremental`: confirm has just written rows that the
    /// stored cursor would skip.
    func reconcile() async {
        await self.sync(.full)
    }
}

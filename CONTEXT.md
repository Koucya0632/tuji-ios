# Tuji — domain & architecture glossary

Shared vocabulary for architecture reviews (`/improve-codebase-architecture`) and
domain modeling. Names for the good seams. Keep terms sharp; add lazily as they crystallize.

## Domain — the atlas (圖鑑)

- **自製圖鑑 (custom atlas)** — a user's own captured items. Created via the capture
  pipeline (photo → AI 識別 → 校正 → confirm). Capacity is quota-gated per tier.
- **公開圖鑑 (public atlas)** — items a user has submitted and that passed the
  moderation gate, visible to everyone. A *submission* is not a publish: the server
  gate may auto-publish, queue for a human, or reject (`AtlasPublishResponse.moderation`).
- **合集 (collection)** — an author's **named, curated set** of their own approved
  public items, scoped to one learning language. Browsed in 公開圖鑑, authored in 我的合集.
  Members can only be the author's already-approved public items (server-enforced).
  Publishing a collection re-runs the text gate on its title + 簡介.
- **Author profile** — a public page for one author: identity + their public items +
  cumulative save count (the altruistic signal).
- **Saving (收藏)** — the *consumption* path. Saving a public item does **not** consume
  the user's 自製圖鑑 capacity.
- **learning direction / target language** — the 合集 and 公開圖鑑 feeds auto-scope to the
  user's current learning language (日文 learners see 日文 collections). No manual switch.

## Architecture — seams & conventions

- **AtlasRepository** — the (currently broad, 25-method) seam over the atlas HTTP API.
  Spans three roles: authoring pipeline, community consumption, and collection
  authoring/browse. Being split by role incrementally as consumers need it.
- **Role seams (emerging)** — narrow protocols carved off `AtlasRepository` as real
  consumers appear. `LiveAtlasRepository` conforms to each via a free extension; tests
  fake only the role.
  - **CollectionEditing** — 5-method seam for the collection-edit screen
    (`collectionEdit`, `updateCollection`, `add/removeCollectionItem`, `publishCollection`).
  - **CollectionsBrowsing** — 1-method seam for the 公開圖鑑 feed (`publicCollections`).
  - **CollectionDetailReading** — 1-method seam for the collection detail (`collection(slug:)`).
  - **AuthorReading** — 1-method seam for the author profile (`author(username:)`).
- **Screen view model convention** — non-trivial screen logic (fetch / paginate / save /
  publish / form + async state) lives in an `@Observable @MainActor` view model,
  `@State`-owned by the View and injected with a narrow repository role via a default arg.
  The View is presentation-only; analytics stays in the View (VMs don't reach
  `AnalyticsService`). Exemplar: `AtlasCaptureVM` (+ `AtlasCaptureVMTests`). All four
  community screens (合集 / 公開圖鑑) are on this pattern: `CollectionEditVM`, `PublicFeedVM`,
  `CollectionDetailVM`, `AuthorProfileVM`.

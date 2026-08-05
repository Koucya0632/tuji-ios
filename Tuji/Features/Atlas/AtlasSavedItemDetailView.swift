// Opens a 社群圖鑑 card from the 圖鑑 page.
//
// Saved community items live in WordsStore as ordinary words (so the theme
// chip, list, badges and search work with no second implementation), but their
// detail screen is not the word detail: these belong to someone else, so the
// destination has an author, a 取消收藏 and a 檢舉. The word payload carries
// none of that, so this fetches the public item by slug and hands off.
//
// The `saved:` id prefix is what routes here — the same convention `atlas:`
// already uses for the owner's own captures, which resolve through the
// owner-scoped detail endpoint instead.

import SwiftUI

struct AtlasSavedItemDetailView: View {
    let slug: String

    @State private var item: AtlasPublicItem?
    @State private var errorMessage: String?

    private let repo: PublicItemsReading

    init(slug: String, repo: PublicItemsReading = LiveAtlasRepository.shared) {
        self.slug = slug
        self.repo = repo
    }

    var body: some View {
        Group {
            if let item {
                AtlasPublicDetailView(item: item)
            } else if let errorMessage {
                self.errorState(errorMessage)
            } else {
                TujiImagePlaceholder()
                    .tint(.tujiTeal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.tujiPaper)
            }
        }
        .task(id: self.slug) { await self.load() }
    }

    private func load() async {
        guard self.item == nil else { return }
        self.errorMessage = nil
        do {
            self.item = try await self.repo.publicItem(slug: self.slug)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// An author who withdrew their item leaves saved copies pointing at
    /// nothing — the same silent disappearance the study queue does. Say so
    /// plainly rather than showing a bare failure.
    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "eye.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tujiInk3)
            Text("這張卡片已經不公開了")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.tujiInk)
            Text(message)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiPaper)
    }
}

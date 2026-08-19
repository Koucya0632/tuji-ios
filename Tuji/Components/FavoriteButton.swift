// Bookmark toggle for a word. Optimistic — updates LocalCache immediately,
// then fires the POST off in the background. Guests get LocalCache only;
// signed-in users also sync to /api/users/favorites.
//
// A bookmark, not a heart: "書籤" is the passive half of the vocabulary split
// (CONTEXT.md) — it means "I want to look at this word again" and never touches
// the study queue. A heart reads as affection or as a like, and this app has a
// separate, *active* action ("收進圖鑑") that does change what you review.
//
// Ink when set, not red: keeping it is not a warning, and `tujiAlert` is
// reserved for errors and destructive actions.

import SwiftUI

struct FavoriteButton: View {
    let wordId: String
    var size: CGFloat = 40

    @Environment(LocalCache.self) private var cache
    @Environment(AuthService.self) private var auth
    /// Injected rather than a hardcoded `.shared` stored property. `ReportFlow`
    /// names that shape as the defect it was carved out to fix — *no init seam,
    /// so no test could substitute it* — and it survived in eight more places.
    private let progress: ProgressRepository

    init(
        wordId: String,
        size: CGFloat = 40,
        progress: ProgressRepository = LiveProgressRepository.shared
    ) {
        self.wordId = wordId
        self.size = size
        self.progress = progress
    }

    private var isFavorite: Bool {
        self.cache.isFavorite(self.wordId)
    }

    var body: some View {
        Button(action: self.toggle) {
            ZStack {
                Rectangle().fill(self.isFavorite ? Color.tujiInk : .tujiPaper2)
                Image(systemName: self.isFavorite ? "bookmark.fill" : "bookmark")
                    .font(.tujiIcon(self.size * 0.38, weight: .semibold))
                    .foregroundStyle(self.isFavorite ? .tujiPaper : .tujiInk2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: self.size, height: self.size)
            .animation(Motion.ease(Motion.d1), value: self.isFavorite)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(self.isFavorite ? "移除書籤" : "加入書籤"))
        .accessibilityAddTraits(self.isFavorite ? [.isSelected] : [])
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.cache.toggleFavorite(self.wordId)

        // Fire-and-forget for signed-in users; guests stay LocalCache-only
        // until they sign in (AuthService.syncLocalCacheToServer handles
        // that catch-up).
        guard case .signedIn = auth.state else { return }
        let nowFav = self.cache.isFavorite(self.wordId)
        Task {
            await self.progress.toggleFavorite(wordId: self.wordId, isFavorite: nowFav)
        }
    }
}

#Preview {
    FavoriteButton(wordId: "tomato")
        .environment(LocalCache.shared)
        .environment(AuthService.shared)
}

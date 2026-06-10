// Heart toggle for a word. Optimistic — updates LocalCache immediately,
// then fires the POST off in the background. Guests get LocalCache only;
// signed-in users also sync to /api/users/favorites.

import SwiftUI

struct FavoriteButton: View {
    let wordId: String
    var size: CGFloat = 40

    @Environment(LocalCache.self) private var cache
    @Environment(AuthService.self) private var auth

    private var isFavorite: Bool {
        self.cache.isFavorite(self.wordId)
    }

    var body: some View {
        Button(action: self.toggle) {
            ZStack {
                Circle()
                    .fill(self.isFavorite ? .tujiCoral.opacity(0.12) : .tujiCard)
                    .overlay(
                        Circle().stroke(
                            self.isFavorite ? Color.tujiCoral : .tujiInk4.opacity(0.3),
                            lineWidth: 1.5
                        )
                    )
                Image(systemName: self.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: self.size * 0.4, weight: .heavy))
                    .foregroundStyle(self.isFavorite ? .tujiCoral : .tujiInk3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: self.size, height: self.size)
        }
        .buttonStyle(.plain)
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        self.cache.toggleFavorite(self.wordId)

        // Fire-and-forget for signed-in users; guests stay LocalCache-only
        // until they sign in (AuthService.syncLocalCacheToServer handles
        // that catch-up).
        guard case .signedIn = auth.state else { return }
        let nowFav = self.cache.isFavorite(self.wordId)
        let payload = FavoritePayload(wordId: self.wordId, op: nowFav ? "add" : "remove")
        Task {
            await APIClient.shared.fireAndForget(.usersFavorites, body: payload)
        }
    }
}

// nonisolated so Encodable conformance escapes MainActor isolation; needed
// because APIClient.fireAndForget requires Body: Sendable.
private nonisolated struct FavoritePayload: Encodable, Sendable {
    let wordId: String
    let op: String
}

#Preview {
    FavoriteButton(wordId: "tomato")
        .environment(LocalCache.shared)
        .environment(AuthService.shared)
}

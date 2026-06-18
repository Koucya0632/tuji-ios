// WordPeek (§III.I).
//
// Lightweight bottom sheet for a quick word preview without leaving the
// current screen. v1 ships .medium with hero + word + favorite + audio
// and a "看完整詳情" CTA that dismisses the sheet and pushes
// WordDetailView. Reused from Cards (long-press) and will plug into
// Favorites / Study-wrong-answer later.

import Nuke
import NukeUI
import SwiftUI

struct WordPeekSheet: View {
    let word: CardWord
    let onSeeMore: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            self.heroImage
            self.headerRow
                .padding(.horizontal, Space.s6)
            Spacer(minLength: 0)
            BBtn(
                title: "看完整詳情",
                bg: .tujiTeal,
                fg: .white,
                fullWidth: true,
                icon: "arrow.right",
                action: self.onSeeMore
            )
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s5)
        }
        .padding(.top, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiBg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationBackground(.tujiBg)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    // MARK: - Bits

    private var heroImage: some View {
        ZStack {
            Rectangle().fill(.tujiTealSoft)
            LazyImage(url: self.word.imageURL) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if state.error != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.tujiInk4)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .pipeline(.shared)
        }
        .frame(height: 188)
        .clipped()
        .clipShape(.rect(cornerRadius: Radius.lg))
        .padding(.horizontal, Space.s5)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(self.word.word)
                    .font(.tujiH1)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !self.word.pronunciation.isEmpty {
                    Text(self.word.pronunciation)
                        .font(.tujiMono)
                        .foregroundStyle(.tujiInk3)
                }
                if self.settings.current.showZh {
                    Text(self.word.chinese)
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk2)
                        .padding(.top, 2)
                }
            }
            Spacer()
            VStack(spacing: Space.s2) {
                FavoriteButton(wordId: self.word.id, size: 44)
                PronunciationButton(text: self.word.word, size: 44)
            }
        }
    }
}

#Preview {
    Text("Tap to peek")
        .sheet(isPresented: .constant(true)) {
            WordPeekSheet(
                word: CardWord(
                    id: "tomato",
                    word: "tomato",
                    chinese: "番茄",
                    imageUrl: "",
                    category: "kitchen",
                    pronunciation: "/təˈmeɪtoʊ/"
                ),
                onSeeMore: {}
            )
        }
        .environment(LocalCache.shared)
        .environment(AuthService.shared)
        .environment(SettingsStore.shared)
}

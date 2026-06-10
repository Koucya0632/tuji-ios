// 2-column grid of every word, filterable by category chip. The store
// fetches once at app launch; this view subscribes via @Environment and
// re-renders when the store updates.
//
// Tapping a tile: stub for now — wired to WordDetailView in W3 part 2.

import SwiftUI

struct CardsListView: View {
    @Environment(WordsStore.self) private var store

    @State private var selectedCategory: String?
    @State private var visibleCount: Int = 60

    private let pageSize: Int = 60

    var body: some View {
        VStack(spacing: 0) {
            header
            chipRow
            content
        }
        .background(.tujiBg)
        .task { await self.store.loadIfNeeded() }
    }

    // MARK: - Bits

    private var header: some View {
        HStack {
            Text("圖鑑")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.tujiInk2)
        }
        .padding(.horizontal, Space.s6)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(label: "全部", value: nil)
                ForEach(self.store.categories, id: \.self) { cat in
                    chip(label: cat, value: cat)
                }
            }
            .padding(.horizontal, Space.s6)
        }
        .padding(.bottom, Space.s3)
    }

    @ViewBuilder
    private var content: some View {
        if self.store.loading, self.store.words.isEmpty {
            VStack {
                Spacer()
                ProgressView().tint(.tujiTeal)
                Text("載入中…")
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .padding(.top, Space.s3)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = store.lastError, self.store.words.isEmpty {
            VStack(spacing: Space.s3) {
                Mascot(pose: .think, size: 80)
                Text("載不到單字")
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                Text(error.localizedDescription)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s6)
                BBtn(title: "重試", fullWidth: false, action: { Task { await self.store.reload() } })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible(), spacing: Space.s3)],
                    spacing: Space.s3
                ) {
                    ForEach(self.visibleWords) { word in
                        Button {
                            // TODO: WordDetailView in W3 part 2
                        } label: {
                            WordTile(word: word)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.s6)

                if self.canShowMore {
                    Button {
                        self.visibleCount += self.pageSize
                    } label: {
                        Text("顯示更多")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.tujiInk3)
                            .padding(.vertical, Space.s4)
                    }
                    .padding(.top, Space.s4)
                } else if self.filtered.isEmpty {
                    Text("這個分類還沒有字")
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk3)
                        .padding(.top, Space.s12)
                }
            }
        }
    }

    private func chip(label: String, value: String?) -> some View {
        let selected = self.selectedCategory == value
        return Button {
            self.selectedCategory = value
            self.visibleCount = self.pageSize
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? .white : .tujiInk2)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
                .background(
                    selected ? .tujiInk : .tujiCard,
                    in: .capsule
                )
                .overlay(
                    Capsule().stroke(.tujiInk4.opacity(selected ? 0 : 0.3), lineWidth: 1)
                )
        }
    }

    private var filtered: [CardWord] {
        self.store.byCategory(self.selectedCategory)
    }

    private var visibleWords: [CardWord] {
        Array(self.filtered.prefix(self.visibleCount))
    }

    private var canShowMore: Bool {
        self.visibleCount < self.filtered.count
    }
}

#Preview {
    CardsListView()
        .environment(WordsStore.shared)
}

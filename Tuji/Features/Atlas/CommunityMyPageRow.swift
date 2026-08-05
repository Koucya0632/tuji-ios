// 「我的公開頁」 — the row at the top of 社群 that leads to your own author page.
//
// This is the new home of the 我的主頁 entry that used to sit in a menu card on
// 我的 (D.7.1). It looks like a contradiction — 社群 is other people's work, and
// the four-tab axis runs 時間 → 內容 → 他人 → 自己, so "you" belongs in the last
// tab. The reason it lives here anyway: what this row opens is not *you*, it is
// **the version of you other people see**. It only makes sense beside their
// work, because that is the shelf yours sits on.
//
// It loads independently of the feed and fails silently. A network problem here
// must not cost the user the collection list below, and a row that renders an
// error where a person's name should be is worse than no row.

import OSLog
import SwiftUI

struct CommunityMyPageRow: View {
    let uid: String

    private let authors: AuthorReading = LiveAtlasRepository.shared
    private let log = Logger(subsystem: "app.tuji.ios", category: "community")

    /// Three states, not one optional. `author == nil` used to mean both "still
    /// loading" and "the fetch failed", so the row rendered nothing in either —
    /// and a view that renders nothing until it has loaded also pops in late and
    /// shoves the list under it down.
    private enum Phase {
        case loading
        case loaded(AtlasAuthor)
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch self.phase {
            case .loading:
                // The shape is known — 72 high with a 40pt avatar — so showing
                // it is honest and the layout does not move when it fills in.
                TujiSkeletonRows(count: 1, height: 72)
            case let .loaded(author):
                NavigationLink(value: NavRoute.authorProfile(handle: author.handle, isSelf: true)) {
                    self.content(author)
                }
                .tujiRowStyle()
            case .failed:
                EmptyView()
            }
        }
        .task { await self.load() }
    }

    private func content(_ author: AtlasAuthor) -> some View {
        HStack(spacing: Space.s3) {
            ProfileAvatar(avatar: author.avatar, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(author.displayName)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                // The two numbers the author page itself shows, in the words it
                // uses there — not the spec's "3 個合集", which counts something
                // the payload does not carry.
                Text(verbatim: "\(tujiLocalized("公開項目")) \(author.publishedCount) · "
                    + "\(tujiLocalized("被收藏")) \(author.saveCount)")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            TujiRowAccessory()
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 72)
        .contentShape(.rect)
    }

    private func load() async {
        if case .loaded = self.phase { return }
        do {
            let author = try await self.authors.author(handle: self.uid, forceReload: false).author
            self.phase = .loaded(author)
        } catch {
            // Still silent to the user: a network problem here must not cost
            // them the collection list below, and an error where a person's
            // name should be is worse than no row. But it is now a *state*, so
            // the row is not indistinguishable from one that never loaded.
            self.log.error("my-page row failed: \(error.localizedDescription, privacy: .public)")
            self.phase = .failed
        }
    }
}

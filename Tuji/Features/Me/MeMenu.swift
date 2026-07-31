// The 我的 tab's two menu cards and the pieces they're built from.
//
// Split out of MeView because the menu is a self-contained concern: it is a
// list of destinations, and the only one that does anything more interesting
// than push a route is 我的公開主頁, which owns its own lookup below.
//
// The grouping is the point. 創作 is what the user makes — 圖鑑管理 and the
// public page it feeds into. 帳號 is the account and the things
// that act on the whole app. Before the split, both lived in one eight-row card
// alongside Pro and 分享, which read as a junk drawer rather than a home.

import SwiftUI

// MARK: - Shared shapes

/// A titled card of rows. The title sits outside the card so the group reads as
/// a heading over a list, not as a first row.
struct MeListCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(self.title)
                .font(.tujiOverline)
                .tracking(2)
                .foregroundStyle(.tujiInk3)
            VStack(spacing: 0) {
                self.content
            }
            .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(.tujiInk4.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

struct MeListRow: View {
    let icon: String
    let title: LocalizedStringKey
    let tint: Color
    var subtitle: LocalizedStringKey?

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: self.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(self.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(self.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tujiInk)
                if let subtitle = self.subtitle {
                    Text(subtitle)
                        .font(.tujiCaption)
                        .foregroundStyle(.tujiInk4)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tujiInk4)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s4)
        .frame(minHeight: 52)
        // Make the whole row (incl. the Spacer gap) tappable, not just the
        // text/icon glyphs.
        .contentShape(Rectangle())
    }
}

private var rowDivider: some View {
    Divider().background(.tujiInk4.opacity(0.15))
}

// MARK: - 創作

/// What the user makes. 我的 is the one home for this — 社群 is other people's
/// work, and an authoring entry point living there made "where is my stuff"
/// have two answers.
///
/// Account-scoped in full, so the caller hides the whole group for guests rather
/// than showing rows that could only fail.
struct MeCreationGroup: View {
    /// The signed-in user's UID, or nil while the session is still settling.
    let uid: String?

    var body: some View {
        MeListCard(title: "創作") {
            NavigationLink(value: NavRoute.atlasManage) {
                MeListRow(icon: "rectangle.stack.fill", title: "圖鑑管理", tint: .tujiTeal)
            }
            .buttonStyle(.plain)
            rowDivider
            MePublicProfileRow(uid: self.uid)
        }
    }
}

/// Opens the user's own author page. No lookup: the UID is already in the
/// session, and there is no longer a second thing this row might do — the
/// consent step it used to branch to no longer exists.
struct MePublicProfileRow: View {
    let uid: String?

    var body: some View {
        // While the session is still settling there is no handle to open, so
        // the row renders as plain text rather than a dead link — the card
        // keeps its shape either way.
        if let uid = self.uid {
            NavigationLink(value: NavRoute.authorProfile(handle: uid, isSelf: true)) {
                self.row
            }
            .buttonStyle(.plain)
        } else {
            self.row
        }
    }

    private var row: some View {
        MeListRow(
            icon: "person.crop.circle.fill",
            title: "我的公開主頁",
            tint: .tujiTeal,
            subtitle: "別人看到的你"
        )
    }
}

// MARK: - 帳號

/// The account itself, and the things that act on the whole app.
struct MeAccountGroup: View {
    let isGuest: Bool
    let shareURL: URL
    let onFeedback: () -> Void

    var body: some View {
        MeListCard(title: "帳號") {
            NavigationLink(value: NavRoute.favorites) {
                MeListRow(icon: "heart.fill", title: "我的收藏", tint: .tujiCoral)
            }
            .buttonStyle(.plain)
            rowDivider
            NavigationLink(value: NavRoute.settings) {
                MeListRow(icon: "gearshape.fill", title: "設定", tint: .tujiInk3)
            }
            .buttonStyle(.plain)
            // 意見收集 is account-scoped; guests have no Bearer token so the
            // submit could only 401 — hidden, matching 創作.
            if !self.isGuest {
                rowDivider
                Button(action: self.onFeedback) {
                    MeListRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "意見收集",
                        tint: .tujiAmber
                    )
                }
                .buttonStyle(.plain)
            }
            rowDivider
            ShareLink(item: self.shareURL) {
                MeListRow(icon: "square.and.arrow.up", title: "分享 App", tint: .tujiTeal)
            }
            // ShareLink has no tap callback — this records "share sheet
            // opened", not a completed share.
            .simultaneousGesture(TapGesture().onEnded {
                AnalyticsService.shared.track(.shareApp)
            })
        }
    }
}

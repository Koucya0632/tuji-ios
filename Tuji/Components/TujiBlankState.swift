// A shelf with nothing on it — because there is nothing, or because the fetch
// failed.
//
// Eleven copies of this lived in 物見/合集/作者主頁/圖鑑管理, and what they
// duplicated was not the layout. It was the decision:
//
//     Text(error == nil ? &lt;this shelf's empty copy&gt; : "載入失敗，請稍後再試")
//     if error != nil { BBtn("重試") { … } }
//
// The failure line was typed out **eight times**. `AtlasAuthorProfileView` had
// already generalised the whole thing into `plainBlank(icon:text:retry:)` — and
// left it `private`, on a view named after one of its callers. The next screen
// could not find it, so the next screen wrote it again.
//
// `MascotEmptyState` and `TujiErrorState` exist in the design system and are
// used 8 and 4 times respectively — but not once inside this feature, because
// they are the full-page treatments and this is the in-shelf one.

import SwiftUI

/// The empty/failed state of a shelf, and which of the two it is.
///
/// The caller says what "nothing here" means for it and how to retry; whether
/// the reader is looking at nothing or at a failure is this module's answer,
/// derived from `error` rather than restated at every call site.
struct TujiBlankState: View {
    /// Why the shelf has nothing on it. Three states, not a `String?`: 作者主頁
    /// and 合集詳情 both distinguish "this does not exist" from "the fetch
    /// failed", and only the second is worth a 重試 button.
    enum Kind {
        /// Nothing here yet — the shelf's own words for that.
        case empty(LocalizedStringKey)
        /// The thing itself is gone or was never public.
        case notFound(LocalizedStringKey)
        /// The load failed. The copy is shared, which is the point: it was
        /// typed out eight times.
        case failed
    }

    /// SF Symbol for the shelf's own idea of emptiness. Absent draws no icon —
    /// two call sites deliberately have none, inside a list that already has
    /// its own visual weight.
    var icon: String?
    var iconSize: CGFloat = 40
    let kind: Kind
    /// Offered only for `.failed`. Absent ⇒ no button at all, for shelves that
    /// reload themselves on the next appearance.
    var retry: (() async -> Void)?
    /// Where the shelf wants it to sit. A screen that centres the state in the
    /// remaining space passes `0` and supplies its own spacers — placement is
    /// the shelf's business; which of the three states this is, is not.
    var topPadding: CGFloat = Space.s5

    /// The common two-state case: a shelf that is either empty or failed.
    init(
        icon: String? = nil,
        iconSize: CGFloat = 40,
        emptyText: LocalizedStringKey,
        error: String?,
        retry: (() async -> Void)? = nil,
        topPadding: CGFloat = Space.s5
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.kind = error == nil ? .empty(emptyText) : .failed
        self.retry = retry
        self.topPadding = topPadding
    }

    init(
        icon: String? = nil,
        iconSize: CGFloat = 40,
        kind: Kind,
        retry: (() async -> Void)? = nil,
        topPadding: CGFloat = Space.s5
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.kind = kind
        self.retry = retry
        self.topPadding = topPadding
    }

    private var message: LocalizedStringKey {
        switch self.kind {
        case let .empty(text): text
        case let .notFound(text): text
        case .failed: "載入失敗，請稍後再試"
        }
    }

    private var offersRetry: Bool {
        if case .failed = self.kind { return self.retry != nil }
        return false
    }

    var body: some View {
        VStack(spacing: Space.s3) {
            if let icon {
                Image(systemName: icon)
                    .font(.tujiIcon(self.iconSize))
                    .foregroundStyle(.tujiInk3)
            }
            Text(self.message)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
            if self.offersRetry, let retry {
                BBtn(title: "重試", fullWidth: false) {
                    Task { await retry() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, self.topPadding)
        .padding(.horizontal, Space.s4)
    }
}

#Preview("empty") {
    TujiBlankState(icon: "square.stack.3d.up", kind: .empty("這個語言還沒有公開合集"))
        .background(.tujiPaper)
}

#Preview("not found") {
    TujiBlankState(
        icon: "person.crop.circle.badge.questionmark",
        kind: .notFound("找不到這個作者")
    )
    .background(.tujiPaper)
}

#Preview("failed") {
    TujiBlankState(icon: "square.stack.3d.up", kind: .failed, retry: {})
        .background(.tujiPaper)
}

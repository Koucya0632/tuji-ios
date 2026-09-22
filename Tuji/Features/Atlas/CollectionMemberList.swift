// 編輯合集 的「卡片」區塊：標題列、新增、每一列，以及長清單的折疊。
//
// 自己一個檔案，因為這一塊會長：一個合集可以有幾十張卡片，而 72pt 一列的清單如果整份
// 攤開，這個畫面自己的送審按鈕就會被推到兩千點以外。折疊的規則（先五列、其餘一鍵展開）
// 是這個元件的事，不是那份表單的事。

import Nuke
import NukeUI
import SwiftUI

struct CollectionMemberList: View {
    let members: [AtlasPublicItem]
    let errorMessage: String?
    /// Owned by the screen: 加入一張卡片 has to be able to open the list, because a
    /// new card lands at the *end* of the roster.
    @Binding var showsAll: Bool
    let onAdd: () -> Void
    let onRemove: (AtlasPublicItem) -> Void

    /// How many rows the roster draws before it asks. A row is 72pt, so thirty
    /// cards would be 2,000pt of scrolling before 公開合集 — the screen's own
    /// commit — came into view. Five is enough to recognise the 合集 by.
    private static let collapsedCount = 5

    private var visible: [AtlasPublicItem] {
        guard !self.showsAll, self.members.count > Self.collapsedCount else { return self.members }
        return Array(self.members.prefix(Self.collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                Text("卡片 \(self.members.count)")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                Spacer(minLength: 0)
                self.addButton
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s2)

            // 加入/移除 refusals belong here, not at the foot of the page: the
            // server's reason for「這個合集不能收未公開的卡片」is about these rows.
            if let errorMessage = self.errorMessage {
                Text(verbatim: errorMessage)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiAlert)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s2)
            }

            if self.members.isEmpty {
                Text("還沒有卡片。點「新增」加入你已確認完成的圖鑑。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            } else {
                // Lazy, because 自製圖鑑 goes to 300 cards on Pro and every one of
                // them is a row with a network image in it. An eager VStack built
                // all 300 the instant 顯示全部 was tapped — and asked the CDN for
                // 300 thumbnails at once — for the ten rows anybody can see.
                //
                // The hairline is the same rule TujiSection draws between its
                // rows, and never after the last one.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(self.visible.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { self.rule }
                        CollectionMemberRow(item: item) { self.onRemove(item) }
                    }
                    if self.members.count > Self.collapsedCount {
                        self.rule
                        self.expander
                    }
                }
            }
        }
        .padding(.top, Space.s5)
    }

    private var rule: some View {
        Rectangle()
            .fill(.tujiRule)
            .frame(height: Border.bw1)
            .padding(.horizontal, Space.s4)
    }

    private var addButton: some View {
        Button(action: self.onAdd) {
            HStack(spacing: Space.s1) {
                Image(systemName: "plus")
                    .font(.tujiIcon(12, weight: .bold))
                Text("新增")
                    .font(.tujiLabel)
                    .tracking(0.5)
            }
            .foregroundStyle(.tujiInk)
            .padding(.horizontal, Space.s3)
            .frame(height: 32)
            .background(.tujiPaper2)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The roster's last row: it says how many are hidden and takes one tap to
    /// show them. A chevron rather than a colour, because teal in this system
    /// means 累積, not 可點.
    private var expander: some View {
        Button {
            withAnimation(Motion.ease(Motion.d2)) { self.showsAll.toggle() }
        } label: {
            HStack(spacing: Space.s2) {
                Text(self.showsAll ? "收合" : "顯示全部 \(self.members.count) 張")
                    .font(.tujiLabel)
                    .tracking(0.5)
                Image(systemName: self.showsAll ? "chevron.up" : "chevron.down")
                    .font(.tujiIcon(11, weight: .bold))
            }
            .foregroundStyle(.tujiInk)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// One member of the 合集 being edited: the photograph, its name, its own review
/// state, and the one thing this screen can do to it.
///
/// A type rather than a method on the screen, because 編輯合集 already shares a
/// file with four other screens and the row is the part of it most likely to be
/// read on its own.
struct CollectionMemberRow: View {
    let item: AtlasPublicItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            // The container owns the box — see AtlasPublicTile for what a photo
            // that sizes itself does to the layout around it.
            Color.tujiPaper2
                .frame(width: 52, height: 52)
                .overlay {
                    LazyImage(url: self.item.imageURL) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else if state.error != nil {
                            Image(systemName: "photo").foregroundStyle(.tujiInk3)
                        } else {
                            TujiImagePlaceholder()
                        }
                    }
                    .pipeline(.shared)
                }
                .clipped()

            // The state sits under the name rather than out at the trailing
            // edge: at accessibility type sizes a chip, a name and a 44pt button
            // cannot share one line, and the name is what must not be cut.
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: self.item.lemma)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(2)
                if let status = self.item.collectionMemberStateLabel {
                    TujiStatusEdgeLabel(
                        text: Text(verbatim: status),
                        edge: self.item.publicationState == "public" ? .tujiAccumulation : .tujiCurrent
                    )
                }
            }
            .padding(.vertical, Space.s2)

            Spacer(minLength: Space.s2)

            Button {
                self.onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.tujiIcon(15, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.leading, Space.s4)
        .padding(.trailing, Space.s1)
        .frame(minHeight: 72)
        // One element per member, with 移除 offered as an action — twenty rows of
        // "從合集移除, button" is not a list anyone can listen to.
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("從合集移除")) {
            self.onRemove()
        }
    }
}

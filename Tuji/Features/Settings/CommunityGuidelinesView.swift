// 平台公約 — what may and may not go onto 物見, written for the people who put it there.
//
// The binding text is the Terms of Service (§5–7, on the web). This page is the
// readable version of the same rules, and it has to stay true to how the app
// actually behaves: a card reaches 物見 only inside a 合集 that passed review,
// blocking hides one way and never touches cards already taken in, and 取消公開
// is the way out that does not cost savers their progress. If any of those
// change, the sentence here changes with it.
//
// Native rather than a web page so it follows the interface language and reads
// in the app's own type, like the rest of the About section.

import SwiftUI

struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tuji 想做的是一本大家一起長出來的圖鑑：你把身邊的東西拍成卡片、整理成合集公開到物見，別人就能拿來學。為了讓物見一直是個能安心學語言的地方，我們和每一位作者約定以下幾件事。")
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.s3)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.tujiRule).frame(width: Border.bw3)
                    }
                    .padding(.top, Space.s4)

                self.section("哪些內容會公開") {
                    self.item(
                        "1. 卡片與合集",
                        body: "圖鑑卡片預設只有你自己看得到。卡片要放進合集、連同合集一起送出審核，全部通過後才會出現在物見。物見上的內容，所有人都能瀏覽，也能收進自己的圖鑑學習。"
                    )
                    self.item(
                        "2. 作者主頁",
                        body: "每個帳號都有公開的作者主頁，會顯示你的暱稱、簽名、頭像，以及你公開的合集。"
                    )
                }

                self.section("禁止公開的內容") {
                    self.item("1. 違法或有害的內容", lines: [
                        "違反法律，或鼓勵危險、違法行為的內容",
                        "色情、性暗示、血腥暴力等令人不適的內容",
                        "仇恨、歧視、騷擾、威脅或霸凌他人的內容"
                    ])
                    self.item("2. 侵害他人權利的內容", lines: [
                        "未經同意拍到可辨識的他人，尤其是兒童",
                        "證件、信用卡、病歷、密碼、住址等私人資訊",
                        "侵犯著作權、商標或肖像權的圖片與文字，例如翻拍書本或他人作品"
                    ])
                    self.item("3. 干擾學習的內容", lines: [
                        "廣告、垃圾訊息、導流到其他服務",
                        "刻意寫錯的單字、翻譯或讀音",
                        "與學習無關、只為了湊數的卡片"
                    ])
                    Text("以上規則同樣適用於暱稱、簽名、頭像與合集名稱。")
                        .font(.tujiBody)
                        .foregroundStyle(.tujiInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                self.section("審核與處理") {
                    self.item(
                        "1. 送出前的審核",
                        body: "送出的卡片與合集會先經過審核。沒有通過的內容只會留在你自己的圖鑑裡，不會出現在物見。"
                    )
                    self.item(
                        "2. 公開後的處理",
                        body: "已公開的內容若違反本公約，我們可能直接將它下架。情節嚴重或一再違反的帳號，可能被限制公開功能或停權。"
                    )
                    self.item(
                        "3. 檢舉與封鎖",
                        body: "看到違反公約的卡片、合集或作者，請直接檢舉。檢舉會送給審核人員，對方不會知道是誰檢舉的。不想再看到某位作者的內容，可以封鎖對方：對方不會收到通知，你已經收進圖鑑的卡片也不受影響。"
                    )
                }

                self.section("你公開的內容") {
                    self.item(
                        "1. 內容仍然屬於你",
                        body: "公開期間，我們會為了在物見上顯示、讓其他人學習而使用它。"
                    )
                    self.item(
                        "2. 想收回就取消公開",
                        body: "取消公開隨時可以做，也可以之後再公開，不會有任何影響。直接刪除公開中的卡片，會讓已經收進的人失去複習進度，所以請先取消公開。"
                    )
                }

                Text("本公約是《使用條款》的一部分，並可能隨功能調整而更新。有任何問題，歡迎透過「意見收集」告訴我們。")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .navigationTitle("平台公約")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s2) {
                Rectangle()
                    .fill(.tujiCurrent)
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.tujiH2)
                    .foregroundStyle(.tujiInk)
            }
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, Space.s5)
    }

    private func item(_ title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text(body)
                .font(.tujiBody)
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func item(_ title: LocalizedStringKey, lines: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            ForEach(lines.indices, id: \.self) { index in
                Text(lines[index])
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Space.s3)
            }
        }
    }
}

#Preview {
    NavigationStack { CommunityGuidelinesView() }
}

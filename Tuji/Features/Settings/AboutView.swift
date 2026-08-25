// Where the app says what it is built out of.
//
// Two obligations meet here. The bundled CJK typeface is GenSenRounded 2 under
// the SIL Open Font License (ADR-0003), which has been shipping unacknowledged;
// and the Japanese furigana data is derived from JMdict via JmdictFurigana, both
// under Creative Commons Attribution-ShareAlike, which asks for exactly this.
//
// Deliberately plain: the licence names and the project names are proper nouns
// and are not translated. Only the framing text is.

import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                TujiSection(title: "資料來源與授權") {
                    self.credit(
                        title: "日文振假名資料",
                        source: "JMdict / JmdictFurigana",
                        licence: "CC BY-SA 4.0",
                        detail: "日文漢字的假名標註來自 JMdict（電子辭書研究開發小組 EDRDG）與 JmdictFurigana。"
                    )
                    self.credit(
                        title: "中日文字型",
                        source: "GenSenRounded 2",
                        licence: "SIL Open Font License 1.1",
                        detail: "思源柔黑體，衍生自 Source Han Sans。"
                    )
                }

                Text("Tuji v\(AppInfo.shortVersion) · 圖記")
                    .font(.tujiLabel)
                    .tracking(0.5)
                    .foregroundStyle(.tujiInk3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Space.s4)
            }
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .navigationTitle("關於")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(
        title: LocalizedStringKey,
        source: String,
        licence: String,
        detail: LocalizedStringKey
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
            Text(source)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk2)
            Text(detail)
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
            Text(licence)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }
}

#Preview {
    NavigationStack { AboutView() }
        .environment(SettingsStore.shared)
}

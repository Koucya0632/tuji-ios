// Where the app says what it is and what it is built out of.
//
// Laid out the way an About page usually is: the icon and version on top, a
// short list in the middle, and the legal documents and copyright at the foot.
// The terms and privacy policy live on the web (the same URLs the paywall and
// the App Store listing point at), so the app links out instead of carrying a
// second copy that would drift.
//
// The credits keep their own page. Two obligations meet there: the bundled CJK
// typeface is GenSenRounded 2 under the SIL Open Font License (ADR-0003), and
// the Japanese furigana data is derived from JMdict via JmdictFurigana, both
// under Creative Commons Attribution-ShareAlike, which asks for exactly this.

import SwiftUI

struct AboutView: View {
    private static let termsURL = URL(string: "https://tuji.nexflow.team/terms") ?? URL(fileURLWithPath: "/")
    private static let privacyURL = URL(string: "https://tuji.nexflow.team/privacy") ?? URL(fileURLWithPath: "/")

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                self.header
                    .padding(.top, Space.s5)

                TujiSection {
                    NavigationLink { AboutCreditsView() } label: {
                        TujiRow("資料來源與授權")
                    }
                    .tujiRowStyle()
                }

                self.footer
                    .padding(.top, Space.s6)
            }
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .navigationTitle("關於")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: Space.s2) {
            Image("about-app-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            // Proper nouns and a version number: nothing here is translated.
            Text(verbatim: "Tuji · 圖記")
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
                .padding(.top, Space.s2)
            Text(verbatim: "Version \(AppInfo.shortVersion) (\(AppInfo.buildNumber))")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Link(destination: Self.termsURL) { Text("使用條款") }
                Text(verbatim: "|")
                    .foregroundStyle(.tujiInk3)
                    .accessibilityHidden(true)
                Link(destination: Self.privacyURL) { Text("隱私權政策") }
            }
            .font(.tujiBodySm)
            .tint(.tujiInk2)

            Text(verbatim: "© 2026 Hong Kuok Wai. All rights reserved.")
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s4)
    }
}

/// Licence names and project names are proper nouns and are not translated.
/// Only the framing text is.
struct AboutCreditsView: View {
    var body: some View {
        ScrollView {
            TujiSection {
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
            .padding(.bottom, Space.s6)
        }
        .background(.tujiPaper)
        .navigationTitle("資料來源與授權")
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

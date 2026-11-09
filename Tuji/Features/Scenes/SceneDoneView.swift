// 練完: every 問句 of the pass with how often it was missed, when the review
// is, and for a non-member the 永久會員 offer with only what it already gives
// (場面練習方案 §3: no scene that is not out yet).

import SwiftUI

struct SceneDoneView: View {
    let scene: PracticeScene
    let summary: ScenePracticeSession.Summary

    @Environment(SettingsStore.self) private var settings
    @Environment(TabNavigator.self) private var navigator
    @Environment(\.presentPaywall) private var presentPaywall
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("場面練習")
                            .font(.tujiLabel)
                            .tracking(1)
                            .foregroundStyle(.tujiInk2)
                        Text("\(self.scene.title.resolved(self.language))練完了")
                            .font(.tujiH2)
                            .foregroundStyle(.tujiInk)
                    }
                    .padding(.top, Space.s4)
                    let practised = SceneProgressStore.shared.book
                    let flags = self.scene.practised(in: practised)
                    HStack(spacing: Space.s3) {
                        SceneSegments(practised: flags)
                        Text(verbatim: "\(flags.count(where: \.self)) / \(flags.count)")
                            .font(.tujiBodySm(.strong))
                            .foregroundStyle(.tujiAccumulation)
                    }
                    .padding(.top, Space.s3)
                    self.results.padding(.top, Space.s3)
                    if LiveEffectiveEntitlement.shared.tier == .free {
                        self.memberOffer.padding(.top, 12)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            }
            VStack(spacing: Space.s1) {
                Button { self.dismiss() } label: {
                    Text("進店前看一眼")
                        .font(.tujiLabel)
                        .underline()
                        .foregroundStyle(.tujiInk2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button { self.navigator.popToRoot() } label: {
                    Text("完成")
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s3)
                        .background(.tujiCurrent)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)
        }
        .background(.tujiPaper)
    }

    private var language: UILanguage {
        self.settings.current.uiLanguage
    }

    private var results: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.tujiRule).frame(height: 1)
            ForEach(self.summary.results) { result in
                HStack {
                    Text(verbatim: result.question.meaning?.resolved(self.language) ?? "")
                        .lineLimit(1)
                    Spacer(minLength: Space.s2)
                    if result.usedHint, result.wrongTries == 0 {
                        Text("用了提示")
                            .font(.tujiLabel)
                            .padding(.horizontal, Space.s2)
                            .frame(height: 24)
                            .background(.tujiPaper2)
                    }
                    if result.wrongTries > 0 {
                        HStack(spacing: 0) {
                            Rectangle().fill(.tujiAlert).frame(width: 3)
                            Text("答錯 \(result.wrongTries) 次")
                                .font(.tujiLabel)
                                .padding(.leading, 8)
                                .padding(.trailing, 8)
                        }
                        .frame(height: 24)
                        .background(.tujiPaper2)
                    }
                }
                .font(.tujiBodySm(.strong))
                .foregroundStyle(.tujiInk2)
                .frame(minHeight: 36)
                Rectangle().fill(.tujiRule).frame(height: 1)
            }
        }
    }

    private var memberOffer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("永久會員")
                .font(.tujiLabel)
                .tracking(1)
                .foregroundStyle(.tujiInk2)
            Text("全部官方主題都能學，例如旅遊組合裡的餐廳、溫泉旅館、交通工具。另外有自製圖鑑和點數。")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk)
                .fixedSize(horizontal: false, vertical: true)
            Button { self.presentPaywall() } label: {
                Text("看永久會員方案")
                    .font(.tujiBody(.strong))
                    .foregroundStyle(.tujiPaper)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.tujiInk)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .overlay(Rectangle().strokeBorder(.tujiRule, lineWidth: 1))
    }
}

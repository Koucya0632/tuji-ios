// Step 1 of the run-in: which atlas. Also shown on its own to a signed-in
// account that has no direction yet.
//
// Tapping a choice is the whole answer — there is no 下一步, because a
// two-option question with a confirm button is two taps for one decision.

import SwiftUI

struct LearningDirectionOnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepBar(step: .language)
            // Wrapped in a scroll view so large Dynamic Type sizes on small
            // screens (e.g. iPhone SE) can scroll to see the full content.
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Spacer(minLength: 0)
                        MascotSpeechBubble(pose: .wave, text: "嗨，我是 Moira！")
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("你想從哪個圖鑑開始？")
                                .font(.tujiH1)
                                .foregroundStyle(.tujiInk)
                            Text("可隨時在設定切換圖鑑，學習進度會分開保留。")
                                .font(.tujiBodySm)
                                .foregroundStyle(.tujiInk3)
                        }
                        VStack(spacing: Space.s2) {
                            self.option(.zhEn, glyph: "EN")
                            self.option(.zhJa, glyph: "あ")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s5)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .background(Color.tujiPaper.ignoresSafeArea())
    }

    private func option(
        _ direction: LearningDirection,
        glyph: String
    )
        -> some View
    {
        OnboardingChoice(
            title: Text(verbatim: direction.title),
            detail: Text(verbatim: direction.atlasSubtitle),
            selected: false,
            action: { self.choose(direction) }
        ) {
            // The script itself, not a flag: it is the language being learned,
            // so it does not translate with the interface.
            Text(verbatim: glyph)
                .font(.tujiH1)
                .accessibilityHidden(true)
        }
    }

    private func choose(_ direction: LearningDirection) {
        // Signed out there is nowhere to persist to — this picker runs before
        // Welcome as well as for an account with no direction yet. The store
        // owns the consequences (LearningDirectionRefresh): a first-run 日文
        // learner must not keep the English mastery, progress and streak the
        // default direction fetched.
        self.settings.setLearningDirection(direction, persist: self.auth.isSignedIn)
    }
}

#Preview {
    LearningDirectionOnboardingView()
        .environment(SettingsStore.shared)
        .environment(AuthService.shared)
}

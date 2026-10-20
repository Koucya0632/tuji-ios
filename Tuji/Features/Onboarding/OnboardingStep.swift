// The run-in a new user walks before 今天: pick a language, make an account.
// The account's first settings are written without asking (SetupView), and
// the feature tour then takes over inside the app, so neither is a step here.
//
// There used to be three marketing pages between the language and the
// account. They told a user what the app does before letting them do it, and
// every page of that is a cost paid before the first word (D.11.4) — so they
// are gone, and the two screens that remain share one step bar.

import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case language, account
}

/// The D.10 step bar, cut into the onboarding's steps.
struct OnboardingStepBar: View {
    let step: OnboardingStep

    var body: some View {
        TujiStepIndicator(total: OnboardingStep.allCases.count, current: self.step.rawValue)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
    }
}

/// A full-width choice on paper2 that inverts to an ink block when chosen
/// (D.11.4).
struct OnboardingChoice<Trailing: View>: View {
    let title: Text
    let detail: Text
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    self.title
                        .font(.tujiH2)
                    self.detail
                        .font(.tujiBodySm)
                        .opacity(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                self.trailing()
            }
            .padding(.horizontal, Space.s4)
            .frame(maxWidth: .infinity, minHeight: 96)
        }
        .buttonStyle(OnboardingChoiceStyle(selected: self.selected))
        .accessibilityAddTraits(self.selected ? .isSelected : [])
    }
}

/// Pressed reads as chosen: the language step advances on tap, so the press
/// is the only moment its selection is ever visible.
private struct OnboardingChoiceStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let inverted = self.selected || configuration.isPressed
        configuration.label
            .foregroundStyle(inverted ? Color.tujiPaper : .tujiInk)
            .background(inverted ? Color.tujiInk : .tujiPaper2, in: .rect(cornerRadius: Radius.r0))
            .animation(Motion.ease(Motion.d1), value: inverted)
    }
}

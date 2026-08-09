// Confirmation dialogs — replaces the system `alert` / `confirmationDialog`.
//
// Centred, not a bottom sheet: this asks for a *decision*, and a sheet is the
// shape the app uses for choosing among options. The 3pt edge along the top is
// the same mark the tab bar, sheets and selected states use.
//
// The mascot does not appear on destructive prompts. Asking someone to confirm
// something irreversible while a cat waves at them is flippant — the same reason
// C.6 keeps it out of error states.

import SwiftUI

enum TujiPromptStyle {
    case confirmation
    case success
    case error
    case destructive

    /// `nil` = no mascot. Destructive and error prompts are deliberately bare.
    fileprivate var mascotPose: MascotPose? {
        switch self {
        case .confirmation: .think
        case .success: .cheer
        case .error, .destructive: nil
        }
    }

    /// The 3pt top edge. Alert for anything the user might regret.
    fileprivate var edgeColor: Color {
        switch self {
        case .error, .destructive: .tujiAlert
        default: .tujiInk
        }
    }
}

enum TujiPromptButtonRole {
    case primary
    case cancel
    case destructive
}

struct TujiPromptAction {
    let title: LocalizedStringKey
    var role: TujiPromptButtonRole = .primary
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        role: TujiPromptButtonRole = .primary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.role = role
        self.action = action
    }
}

private struct TujiPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let style: TujiPromptStyle
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let detail: LocalizedStringKey?
    let primary: TujiPromptAction
    let secondary: TujiPromptAction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!self.isPresented)
                .accessibilityHidden(self.isPresented)

            if self.isPresented {
                Color.tujiScrim
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                self.prompt
                    .padding(.horizontal, Space.s4)
                    .transition(
                        self.reduceMotion
                            ? .opacity
                            : .scale(scale: 0.98).combined(with: .opacity)
                    )
                    .zIndex(1)
            }
        }
        .animation(
            self.reduceMotion ? nil : Motion.ease(Motion.d2),
            value: self.isPresented
        )
    }

    private var prompt: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(self.style.edgeColor)
                .frame(height: Border.bw3)
            self.card
        }
        .frame(maxWidth: 340)
        .background(.tujiPaper)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 0) {
            if let pose = self.style.mascotPose {
                MascotFigure(pose: pose, size: 64, grounding: .none)
                    .accessibilityHidden(true)
                    .padding(.bottom, Space.s3)
            }

            Text(self.title)
                .font(.tujiH2)
                .foregroundStyle(.tujiInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(.tujiBody)
                    .foregroundStyle(.tujiInk2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s2)
            }

            if let detail {
                self.detailRow(detail)
                    .padding(.top, Space.s3)
            }

            self.buttons
                .padding(.top, Space.s4)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
    }

    private func detailRow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.tujiBodySm)
            .foregroundStyle(.tujiInk2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s3)
            .background(.tujiPaper2)
    }

    /// Stacked, not side by side. Two buttons of equal width read as equally
    /// weighted choices; the decision here has a primary and a way out.
    private var buttons: some View {
        VStack(spacing: Space.s2) {
            self.actionButton(self.primary)
            if let secondary {
                self.textButton(secondary)
            }
        }
    }

    private func actionButton(_ item: TujiPromptAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.isPresented = false
            item.action()
        } label: {
            Text(item.title)
                .font(.tujiH3)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(PromptActionStyle(destructive: item.role == .destructive))
    }

    private func textButton(_ item: TujiPromptAction) -> some View {
        Button {
            self.isPresented = false
            item.action()
        } label: {
            Text(item.title)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk2)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Destructive actions invert on press instead of just changing ground — that
/// tap has weight, and the colour arriving under the finger says so.
private struct PromptActionStyle: ButtonStyle {
    let destructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(self.foreground(pressed: configuration.isPressed))
            .background(self.ground(pressed: configuration.isPressed))
            .animation(Motion.ease(Motion.d1), value: configuration.isPressed)
    }

    private func foreground(pressed: Bool) -> Color {
        guard self.destructive else { return .tujiInk }
        return pressed ? .tujiPaper : .tujiAlert
    }

    private func ground(pressed: Bool) -> Color {
        if self.destructive {
            return pressed ? .tujiAlert : .tujiPaper2
        }
        return pressed ? .tujiCurrentDeep : .tujiCurrent
    }
}

extension View {
    func tujiPrompt(
        isPresented: Binding<Bool>,
        style: TujiPromptStyle,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        detail: LocalizedStringKey? = nil,
        primary: TujiPromptAction,
        secondary: TujiPromptAction? = nil
    )
        -> some View
    {
        modifier(
            TujiPromptModifier(
                isPresented: isPresented,
                style: style,
                title: title,
                message: message,
                detail: detail,
                primary: primary,
                secondary: secondary
            )
        )
    }
}

#Preview {
    @Previewable @State var presented = true

    Color.tujiPaper
        .ignoresSafeArea()
        .tujiPrompt(
            isPresented: $presented,
            style: .confirmation,
            title: "要離開這次學習嗎？",
            message: "目前進度會保留，下次可以繼續。",
            primary: TujiPromptAction("先離開") {},
            secondary: TujiPromptAction("繼續學習", role: .cancel) {}
        )
}

import SwiftUI

enum TujiPromptStyle {
    case confirmation
    case success
    case error
    case destructive

    fileprivate var mascotPose: MascotPose? {
        switch self {
        case .confirmation: .think
        case .success: .cheer
        case .error: .peek
        case .destructive: nil
        }
    }

    fileprivate var cardColor: Color {
        switch self {
        case .success: .tujiEye
        default: .tujiPaper
        }
    }

    fileprivate var shadowColor: Color {
        switch self {
        case .error, .destructive: .tujiAlert
        default: .tujiTealDeep
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
                Color.tujiInk
                    .opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                prompt
                    .padding(.horizontal, Space.s4)
                    .transition(
                        self.reduceMotion
                            ? .opacity
                            : .scale(scale: 0.92).combined(with: .opacity)
                    )
                    .zIndex(1)
            }
        }
        .animation(
            self.reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.16),
            value: self.isPresented
        )
    }

    private var prompt: some View {
        ZStack(alignment: mascotAlignment) {
            card
                .padding(.top, self.style.mascotPose == nil ? 0 : 38)

            if let pose = self.style.mascotPose {
                MascotFigure(
                    pose: pose,
                    size: self.style == .success ? 112 : 96,
                    grounding: .none
                )
                .padding(.horizontal, self.style == .success ? 0 : Space.s3)
                .offset(x: mascotOffset.width, y: mascotOffset.height)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 390)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var mascotAlignment: Alignment {
        switch self.style {
        case .confirmation: .topLeading
        case .success: .top
        case .error: .topTrailing
        case .destructive: .top
        }
    }

    private var mascotOffset: CGSize {
        switch self.style {
        case .confirmation: CGSize(width: 4, height: -5)
        case .success: CGSize(width: 0, height: -14)
        case .error: CGSize(width: -2, height: -5)
        case .destructive: .zero
        }
    }

    private var card: some View {
        VStack(spacing: Space.s3) {
            header

            if let message {
                Text(message)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail {
                detailRow(detail)
            }

            buttons
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, self.style.mascotPose == nil ? Space.s4 : Space.s5)
        .padding(.bottom, Space.s4)
        .frame(maxWidth: .infinity)
        .background(self.style.cardColor, in: .rect(cornerRadius: Radius.r0))
        .background {
            RoundedRectangle(cornerRadius: Radius.r0)
                .fill(self.style.shadowColor)
                .offset(y: 6)
        }
        .overlay(cardOverlay)
    }

    private var header: some View {
        VStack(spacing: Space.s3) {
            if self.style == .destructive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.tujiAlert)
            } else if self.style == .error {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(.tujiAlert)
            }

            Text(self.title)
                .font(.tujiH3)
                .foregroundStyle(.tujiInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: Radius.r0)
            .stroke(
                self.style == .destructive
                    ? Color.tujiAlert.opacity(0.72)
                    : Color.tujiInk.opacity(0.08),
                lineWidth: self.style == .destructive ? 1.5 : 1
            )

        if self.style == .error {
            VStack {
                Capsule()
                    .fill(.tujiAlert)
                    .frame(width: 72, height: 5)
                    .padding(.top, Space.s2)
                Spacer()
            }
        }
    }

    private func detailRow(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tujiTeal)
            Text(text)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
    }

    @ViewBuilder
    private var buttons: some View {
        switch self.style {
        case .success:
            promptButton(self.primary)

        case .error:
            VStack(spacing: Space.s3) {
                promptButton(self.primary)
                if let secondary {
                    promptButton(secondary)
                }
            }

        case .confirmation, .destructive:
            HStack(spacing: Space.s3) {
                if let secondary {
                    promptButton(secondary)
                }
                promptButton(self.primary)
            }
        }
    }

    private func promptButton(_ item: TujiPromptAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.isPresented = false
            item.action()
        } label: {
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(buttonForeground(for: item.role))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .padding(.horizontal, Space.s3)
                .background(buttonBackground(for: item.role))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.r0)
                        .stroke(buttonBorder(for: item.role), lineWidth: 1.5)
                )
                .clipShape(.rect(cornerRadius: Radius.r0))
        }
        .buttonStyle(.plain)
    }

    private func buttonForeground(for role: TujiPromptButtonRole) -> Color {
        switch role {
        case .primary, .destructive: .white
        case .cancel: .tujiInk
        }
    }

    private func buttonBackground(for role: TujiPromptButtonRole) -> Color {
        switch role {
        case .primary: .tujiTeal
        case .destructive: .tujiAlert
        case .cancel: .tujiPaper
        }
    }

    private func buttonBorder(for role: TujiPromptButtonRole) -> Color {
        switch role {
        case .cancel: .tujiInk3
        case .primary, .destructive: .clear
        }
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

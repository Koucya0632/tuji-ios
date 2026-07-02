import SwiftUI

enum TujiStatusToastStyle {
    case recognizing
    case deleting

    var title: LocalizedStringKey {
        switch self {
        case .recognizing: "AI 識別中…"
        case .deleting: "刪除中…"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .recognizing: "正在分析圖片"
        case .deleting: "請稍候"
        }
    }

    var icon: String {
        switch self {
        case .recognizing: "sparkles"
        case .deleting: "trash"
        }
    }

    var tint: Color {
        switch self {
        case .recognizing: .tujiTeal
        case .deleting: .tujiCoral
        }
    }
}

private struct TujiStatusToastModifier: ViewModifier {
    let isPresented: Bool
    let style: TujiStatusToastStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!self.isPresented)

            if self.isPresented {
                Color.tujiBgInk
                    .opacity(0.16)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)

                TujiStatusToast(style: self.style)
                    .transition(
                        self.reduceMotion
                            ? .opacity
                            : .scale(scale: 0.94).combined(with: .opacity)
                    )
                    .zIndex(1)
            }
        }
        .animation(
            self.reduceMotion ? nil : .spring(duration: 0.24, bounce: 0.12),
            value: self.isPresented
        )
    }
}

private struct TujiStatusToast: View {
    let style: TujiStatusToastStyle

    var body: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(self.style.tint.opacity(0.12))
                    .frame(width: 48, height: 48)

                ProgressView()
                    .controlSize(.regular)
                    .tint(self.style.tint)
                    .frame(width: 48, height: 48)

                Image(systemName: self.style.icon)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(self.style.tint)

                Circle()
                    .fill(.tujiYellow)
                    .frame(width: 7, height: 7)
                    .offset(x: 18, y: -15)
            }
            .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text(self.style.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.tujiInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(self.style.detail)
                    .font(.tujiCaption)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
            }
        }
        .frame(width: 136, height: 136)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.tujiCard.opacity(0.86))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.74), lineWidth: 1)
        }
        .tujiCardShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.style.title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    func tujiStatusToast(
        isPresented: Bool,
        style: TujiStatusToastStyle
    )
        -> some View
    {
        modifier(TujiStatusToastModifier(isPresented: isPresented, style: style))
    }
}

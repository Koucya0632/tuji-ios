import SwiftUI

enum MascotBubbleTone {
    case neutral, success, error

    var background: Color {
        switch self {
        case .neutral: .tujiTealSoft
        case .success: .tujiTeal
        case .error: .tujiAlert
        }
    }

    var foreground: Color {
        switch self {
        case .neutral: .tujiInk
        case .success, .error: .white
        }
    }
}

/// A compact study prompt where the mascot visibly leans out of the bubble.
struct MascotSpeechBubble: View {
    let pose: MascotPose
    let text: LocalizedStringKey
    var tone: MascotBubbleTone = .neutral
    var systemImage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            MascotFigure(pose: self.pose, size: 56)
                .id(self.pose)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .frame(width: 50, alignment: .center)
                .zIndex(1)

            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(self.text)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(self.tone.foreground)
            .padding(.leading, Space.s3)
            .padding(.trailing, Space.s3)
            .frame(minHeight: 40)
            .background(self.tone.background, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(.tujiInk.opacity(self.tone == .neutral ? 0.08 : 0), lineWidth: 1)
            )
            .offset(x: -8)

            Spacer(minLength: 0)
        }
        .animation(self.reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.18), value: self.pose)
    }
}

/// A reusable empty/error panel. The mascot rests on the card edge rather
/// than floating independently in the page.
struct MascotEmptyState<Actions: View>: View {
    let pose: MascotPose
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    var compact: Bool
    let actions: Actions

    init(
        pose: MascotPose,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        compact: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.pose = pose
        self.title = title
        self.message = message
        self.compact = compact
        self.actions = actions()
    }

    var body: some View {
        let figureSize: CGFloat = self.compact ? 104 : 124
        let overlap: CGFloat = self.compact ? 16 : 20
        let lift = max(0, self.pose.visibleHeightRatio * figureSize - overlap)

        ZStack(alignment: .top) {
            VStack(spacing: Space.s3) {
                Text(self.title)
                    .font(.tujiH3)
                    .foregroundStyle(.tujiInk)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                        .multilineTextAlignment(.center)
                }
                self.actions
                    .padding(.top, Space.s1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, self.compact ? Space.s3 : Space.s4)
            .padding(.top, overlap + Space.s4)
            .padding(.bottom, self.compact ? Space.s3 : Space.s4)
            .background(.tujiPaper, in: .rect(cornerRadius: Radius.r0))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(.tujiRule.opacity(0.22), lineWidth: 1)
            )
            .padding(.top, lift)

            MascotFigure(pose: self.pose, size: figureSize)
        }
        .frame(maxWidth: 420)
    }
}

extension MascotEmptyState where Actions == EmptyView {
    init(pose: MascotPose, title: LocalizedStringKey, message: LocalizedStringKey? = nil, compact: Bool = false) {
        self.init(pose: pose, title: title, message: message, compact: compact) {
            EmptyView()
        }
    }
}

/// Celebration hero used by study completion and milestones.
struct MascotCelebrationCard<Detail: View>: View {
    let pose: MascotPose
    let title: LocalizedStringKey
    var accent: Color = .tujiEye
    var dark = false
    let detail: Detail

    init(
        pose: MascotPose = .cheer,
        title: LocalizedStringKey,
        accent: Color = .tujiEye,
        dark: Bool = false,
        @ViewBuilder detail: () -> Detail
    ) {
        self.pose = pose
        self.title = title
        self.accent = accent
        self.dark = dark
        self.detail = detail()
    }

    var body: some View {
        let figureSize: CGFloat = 132
        let overlap: CGFloat = 24
        let lift = max(0, self.pose.visibleHeightRatio * figureSize - overlap)

        ZStack(alignment: .top) {
            VStack(spacing: Space.s3) {
                Text(self.title)
                    .font(.tujiH2)
                    .foregroundStyle(self.dark ? .white : .tujiInk)
                    .multilineTextAlignment(.center)
                self.detail
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.s4)
            .padding(.top, overlap + Space.s4)
            .padding(.bottom, Space.s4)
            .background(
                self.dark ? Color.tujiInk : self.accent.opacity(0.32),
                in: .rect(cornerRadius: Radius.r0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.r0)
                    .stroke(
                        self.dark ? Color.white.opacity(0.16) : self.accent.opacity(0.72),
                        lineWidth: 1
                    )
            )
            .padding(.top, lift)

            MascotFigure(pose: self.pose, size: figureSize, grounding: self.dark ? .glow : .shadow)
        }
        .frame(maxWidth: 440)
    }
}

/// Consistent profile/avatar treatment for the hero and picker cells.
struct MascotAvatar: View {
    let pose: MascotPose
    var size: CGFloat = 88
    var selected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.tujiTealSoft, .tujiEye.opacity(0.26)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Mascot(pose: self.pose, size: self.size * 0.88)
        }
        .frame(width: self.size, height: self.size)
        .clipShape(.circle)
        .overlay(
            Circle()
                .stroke(
                    self.selected ? Color.tujiTeal : .tujiInk.opacity(0.08),
                    lineWidth: self.selected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

/// A public profile avatar. HTTPS images render in the circular frame; every
/// other stored value collapses to the one built-in black-cat default.
struct ProfileAvatar: View {
    let avatar: String?
    var fallbackPose: MascotPose = .face
    var size: CGFloat = 88
    var selected = false

    private var imageURL: URL? {
        guard let avatar, let url = URL(string: avatar), url.scheme == "https" else { return nil }
        return url
    }

    var body: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if phase.error != nil {
                    MascotAvatar(pose: self.fallbackPose, size: self.size, selected: self.selected)
                } else {
                    ProgressView().tint(.tujiTeal)
                }
            }
            .frame(width: self.size, height: self.size)
            .background(.tujiTealSoft)
            .clipShape(.circle)
            .overlay(
                Circle()
                    .stroke(
                        self.selected ? Color.tujiTeal : .tujiInk.opacity(0.08),
                        lineWidth: self.selected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        } else {
            MascotAvatar(
                pose: self.fallbackPose,
                size: self.size,
                selected: self.selected
            )
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Space.s5) {
            MascotSpeechBubble(pose: .think, text: "這個是什麼？")
            MascotSpeechBubble(
                pose: .cheer,
                text: "答對了！",
                tone: .success,
                systemImage: "checkmark.circle.fill"
            )
            MascotEmptyState(pose: .sleep, title: "今天沒有待複習", message: "休息一下，明天再來")
            MascotCelebrationCard(title: "複習完成！") {
                Text("8 個字").font(.tujiH3)
            }
            HStack {
                MascotAvatar(pose: .face)
                MascotAvatar(pose: .wave, selected: true)
            }
        }
        .padding()
    }
    .background(.tujiPaper)
}

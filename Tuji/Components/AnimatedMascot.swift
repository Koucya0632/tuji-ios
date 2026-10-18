import SwiftUI
import UIKit

/// The only looping motion on the assistant home. The rest of the app keeps
/// Motion's interaction curves; the cat's breathing/gestures have their own clock.
struct AnimatedMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var started = Date()
    @State private var blinkStarted: Date?
    @State private var wagStarted: Date?

    private var animating: Bool {
        self.visible && self.scenePhase == .active && !self.reduceMotion
    }

    var body: some View {
        Button(action: self.pet) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !self.animating)) { timeline in
                let frame = MascotAnimationFrame(
                    elapsed: timeline.date.timeIntervalSince(self.started),
                    blinkElapsed: self.blinkStarted.map { timeline.date.timeIntervalSince($0) },
                    wagElapsed: self.wagStarted.map { timeline.date.timeIntervalSince($0) },
                    enabled: self.animating
                )
                Canvas { context, size in
                    AnimatedMascotArtwork.shared?.draw(in: &context, size: size, frame: frame)
                }
                .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        // No press dimming: the cat answers by wagging, the moment a finger lands.
        .buttonStyle(MascotPress(onPress: self.wag))
        .accessibilityLabel(Text("摸摸 Tuji"))
        .accessibilityHint(Text("點擊讓 Tuji 甩尾巴"))
        .accessibilityIdentifier("assistant-mascot")
        .onAppear { self.visible = true }
        .onDisappear { self.visible = false }
        .task(id: self.animating) {
            self.blinkStarted = nil
            self.wagStarted = nil
            guard self.animating else { return }
            self.started = Date()
            do {
                try await Task.sleep(for: .seconds(2.1))
                while !Task.isCancelled {
                    self.blinkStarted = Date()
                    try await Task.sleep(for: .seconds(Double.random(in: 3.2...6)))
                }
            } catch {
                // Leaving/backgrounding cancels the one blink scheduler.
            }
        }
    }

    private func wag() {
        if self.animating {
            self.wagStarted = Date()
        }
    }

    private func pet() {
        // A touch already wagged on press; VoiceOver activation never presses.
        if self.wagStarted.map({ Date().timeIntervalSince($0) > 1.65 }) ?? true {
            self.wag()
        }
        if self.reduceMotion || UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: tujiLocalized("Tuji 收到你的摸摸了。"))
        }
    }
}

private struct MascotPress: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { self.onPress() }
            }
    }
}

/// Pure time-to-pose mapping, shared by the Canvas and deterministic frame checks.
struct MascotAnimationFrame {
    enum Eyes: CaseIterable { case open, half, closed }

    let breath: CGFloat
    let wag: CGFloat
    let eyes: Eyes

    init(elapsed: TimeInterval, blinkElapsed: TimeInterval?, wagElapsed: TimeInterval?, enabled: Bool = true) {
        guard enabled else {
            self.breath = 0
            self.wag = 0
            self.eyes = .open
            return
        }
        self.breath = (1 - cos(max(0, elapsed) * .pi * 2 / 3.7)) / 2
        if let wagElapsed, (0..<1.65).contains(wagElapsed) {
            self.wag = sin(wagElapsed * 13)
                * sin(min(wagElapsed / 0.12, 1) * .pi / 2)
                * pow(1 - wagElapsed / 1.65, 1.3)
        } else {
            self.wag = 0
        }
        if let blinkElapsed, (0..<0.22).contains(blinkElapsed) {
            self.eyes = (0.055..<0.14).contains(blinkElapsed) ? .closed : .half
        } else {
            self.eyes = .open
        }
    }
}

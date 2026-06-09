// First-build scaffold — Tuji wordmark + Mascot + smoke test button.
// Replaced wholesale in W2 by RootView + Auth state machine.

import SwiftUI

struct ContentView: View {
    @State private var pinging = false
    @State private var lastResult: SmokeTest.Result?

    var body: some View {
        VStack(spacing: Space.s6) {
            Spacer()

            Mascot(pose: .wave, size: 96)

            HStack(spacing: 0) {
                Text("Tuji")
                Text(".").foregroundStyle(.tujiCoral)
            }
            .font(.tujiH1)
            .foregroundStyle(.tujiInk)

            Text("用圖學英文")
                .font(.tujiBodyLg)
                .foregroundStyle(.tujiInk3)

            Spacer()

            VStack(spacing: Space.s3) {
                BBtn(
                    title: pinging ? "ping..." : "Smoke test",
                    icon: "antenna.radiowaves.left.and.right",
                    action: ping
                )
                .frame(maxWidth: 280)
                .disabled(pinging)

                if let r = lastResult {
                    resultCard(r)
                }
            }

            Spacer()

            buildInfo
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.tujiBg)
    }

    // MARK: - Bits

    @ViewBuilder
    private func resultCard(_ r: SmokeTest.Result) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: r.status == 200 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(r.status == 200 ? .tujiGreen : .tujiCoral)
                Text("HTTP \(r.status)")
                    .font(.tujiOverline)
                    .foregroundStyle(.tujiInk2)
            }
            Text(r.body)
                .font(.tujiMono)
                .foregroundStyle(.tujiInk2)
                .multilineTextAlignment(.leading)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiCard, in: .rect(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(.tujiInk4.opacity(0.3), lineWidth: 1)
        )
    }

    private var buildInfo: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? "?"
        let b = info["CFBundleVersion"] as? String ?? "?"
        let base = info["TUJI_BASE_URL"] as? String ?? "(fallback)"
        return VStack(spacing: 2) {
            Text("v\(v) (\(b))")
            Text(base).lineLimit(1).truncationMode(.middle)
        }
        .font(.tujiCaption)
        .foregroundStyle(.tujiInk4)
    }

    private func ping() {
        Task {
            pinging = true
            defer { pinging = false }
            lastResult = await SmokeTest.whoami()
        }
    }
}

#Preview {
    ContentView()
}

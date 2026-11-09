// A machine on the counter: its touch screen, with native buttons in the
// machine's Japanese, and the hardware under it (card reader, coin slot,
// tray) as separate controls labelled in the interface language.

import SwiftUI

struct MachineView: View {
    let machine: SceneMachine
    let send: (MachineAction) -> Void

    @AccessibilityFocusState private var titleFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let screen = self.machine.screen
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: self.brand)
                    .font(.tujiLabel)
                    .foregroundStyle(.tujiMachineFace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Space.s2)
                    .background(.tujiMachineBar)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: screen.title)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(.tujiMachineBezel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused(self.$titleFocused)
                    if let detail = screen.detail {
                        Text(verbatim: detail)
                            .font(.tujiBodySm)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.tujiMachineBezel)
                    }
                    if let paper = screen.paper {
                        Text(verbatim: paper)
                            .font(.tujiBodySm)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.tujiInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.tujiPaper)
                            .overlay(Rectangle().strokeBorder(
                                .tujiMachineEdge,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            ))
                    }
                    if !screen.buttons.isEmpty {
                        LazyVGrid(columns: self.columns, spacing: 10) {
                            ForEach(screen.buttons) { control in
                                self.screenButton(control)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.tujiMachineFace)
            .environment(\.locale, Locale(identifier: "ja"))
            if !screen.hardware.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(screen.hardware) { control in
                            self.hardwareButton(control)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.tujiMachineBezel)
        .onChange(of: screen.title) { self.titleFocused = true }
    }

    private var brand: String {
        switch self.machine {
        case .payment: "お会計"
        case .ageConfirm: "年齢確認"
        case .foodTicket: "食券販売機"
        case .orderTablet: "テーブル 08"
        }
    }

    private func screenButton(_ control: MachineControl) -> some View {
        Button { self.send(control.action) } label: {
            Text(verbatim: self.label(control))
                .font(.tujiBodySm(.strong))
                .multilineTextAlignment(.center)
                .foregroundStyle(control.isPrimary ? .tujiMachineFace : .tujiMachineBezel)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, Space.s1)
                .background(control.isPrimary ? .tujiMachineBar : .tujiMachineFace)
                .overlay(Rectangle().strokeBorder(.tujiMachineEdge, lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!control.isEnabled)
        .opacity(control.isEnabled ? 1 : 0.45)
    }

    private func hardwareButton(_ control: MachineControl) -> some View {
        Button { self.send(control.action) } label: {
            Label(self.hardwareTitle(control), systemImage: self.hardwareSymbol(control))
                .font(.tujiLabel)
                .foregroundStyle(.tujiPaper)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.tujiInk2)
                .overlay(alignment: .top) { Rectangle().fill(.tujiAccumulationSoft).frame(height: 3) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func label(_ control: MachineControl) -> String {
        if case let .onScreen(text) = control.role { return text }
        return ""
    }

    private func hardwareTitle(_ control: MachineControl) -> LocalizedStringKey {
        guard case let .hardware(part) = control.role else { return "" }
        switch part {
        case .cardReader: return "感應信用卡"
        case let .coinSlot(amount): return "投入 \(yen(amount))"
        case let .tray(withChange): return withChange ? "取找零與收據" : "取收據"
        case .ticketTray: return "取食券與找零"
        }
    }

    private func hardwareSymbol(_ control: MachineControl) -> String {
        guard case let .hardware(part) = control.role else { return "hand.tap" }
        switch part {
        case .cardReader: return "wave.3.right"
        case .coinSlot: return "yensign.circle"
        case .tray, .ticketTray: return "doc.plaintext"
        }
    }
}

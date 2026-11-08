// The register and ordering screens a screen question shows. They are drawn by
// the app rather than photographed: every chain's machine looks different, so a
// photo of one would teach that one (場面練習方案 §4).
//
// Each screen names its buttons by the ids of the question's choices, so a tap
// on 「クレジット」 answers choice `credit`. `SceneContentTests` holds every
// screen question's choices to its screens' buttons.

import Foundation

nonisolated enum ScreenMockKind: String, Decodable, CaseIterable, Sendable {
    case paymentSelect = "payment-select"
    case paymentSelectAlt = "payment-select-alt"
    case ageConfirm = "age-confirm"
    case ticketMachine = "ticket-machine"
    case orderTablet = "order-tablet"

    struct Button: Hashable, Sendable {
        /// The `SceneChoice.id` this button answers.
        let choiceId: String
        let label: String
    }

    /// What the screen says across its top, in Japanese as the machine would.
    var heading: String {
        switch self {
        case .paymentSelect: "お支払い方法を選択してください"
        case .paymentSelectAlt: "お支払い方法"
        case .ageConfirm: "20歳以上ですか？"
        case .ticketMachine: "食券"
        case .orderTablet: "ご注文内容の確認"
        }
    }

    /// Buttons in the order the screen lays them out.
    var buttons: [Button] {
        switch self {
        case .paymentSelect:
            [
                .init(choiceId: "cash", label: "現金"),
                .init(choiceId: "credit", label: "クレジット"),
                .init(choiceId: "emoney", label: "電子マネー"),
                .init(choiceId: "qr", label: "コード決済")
            ]
        case .paymentSelectAlt:
            [
                .init(choiceId: "qr", label: "QR・バーコード"),
                .init(choiceId: "emoney", label: "交通系IC・電子マネー"),
                .init(choiceId: "credit", label: "クレジットカード"),
                .init(choiceId: "cash", label: "現金")
            ]
        case .ageConfirm:
            [
                .init(choiceId: "yes", label: "はい"),
                .init(choiceId: "no", label: "いいえ"),
                .init(choiceId: "back", label: "戻る")
            ]
        case .ticketMachine:
            [
                .init(choiceId: "confirm", label: "購入"),
                .init(choiceId: "cancel", label: "取消"),
                .init(choiceId: "call", label: "呼出"),
                .init(choiceId: "back", label: "戻る")
            ]
        case .orderTablet:
            [
                .init(choiceId: "confirm", label: "注文する"),
                .init(choiceId: "cancel", label: "取り消す"),
                .init(choiceId: "call", label: "店員呼出"),
                .init(choiceId: "back", label: "戻る")
            ]
        }
    }

    func label(for choiceId: String) -> String? {
        self.buttons.first { $0.choiceId == choiceId }?.label
    }
}

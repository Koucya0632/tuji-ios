// The four machines a 場面 can put in front of the traveller: the customer
// payment screen, the age check, the 食券機 and the table tablet.
//
// Each is a value with a pure `send`. What the screen shows is `screen`, built
// from the state; whether the traveller finished, and how, is `outcome`. Taps
// that change nothing (a second tap on a finished machine, 戻る on the first
// screen) leave the state as it was, so nothing a view does twice counts twice.
//
// The Japanese on the screens is the machine's own and is never translated.
// Amounts, items and ticket numbers are examples.

import Foundation

nonisolated enum MachineKind: String, Hashable, Decodable {
    case payment
    case ageConfirm = "age-confirm"
    case foodTicket = "food-ticket"
    case orderTablet = "order-tablet"
    case kiosk
}

/// One line on a machine's menu: a dish on the 食券機, an upgrade on a
/// self-order kiosk. `id` is what a scene's `expect` names.
nonisolated struct MachineMenuItem: Hashable, Decodable {
    let id: String
    let name: String
    let price: Int
}

nonisolated enum PaymentMethod: String, Hashable, Decodable {
    case card
    case cash
}

/// Everything any machine can be told. A machine ignores what it has no use for.
nonisolated enum MachineAction: Hashable {
    case choose(PaymentMethod)
    case back
    case tapCard
    case insert(yen: Int)
    case settle
    case take
    case answerAge(AgeAnswer)
    case pickDish(Int)
    case pickOption(Int)
    case confirmOrder
    case payDishInCash
    case issueTicket
    case pickCategory(TabletCategory)
    case addToCart
    case more
    case fewer
    case review
    case placeOrder
    case showHistory
}

nonisolated enum AgeAnswer: Hashable {
    case yes
    case no
    case cancel
}

nonisolated enum TabletCategory: String, Hashable, CaseIterable {
    case noodles = "麺類"
    case drinks = "飲み物"
}

/// What a finished machine did.
nonisolated enum MachineOutcome: Hashable {
    case paid(PaymentMethod, change: Int)
    case age(AgeAnswer)
    /// `item` is the menu item's id.
    case ticket(item: String, change: Int)
    /// `option` is the kiosk menu item's id.
    case kioskOrder(option: String, total: Int)
    case ordered(item: String, count: Int, total: Int)
}

/// One control on a machine. `onScreen` controls are the touch screen's own
/// buttons, labelled in Japanese; the others are hardware the traveller uses
/// with their hands (the card reader, the coin slot, the tray), labelled in
/// the interface language by the view.
nonisolated struct MachineControl: Hashable, Identifiable {
    enum Role: Hashable {
        case onScreen(String)
        case hardware(Hardware)
    }

    enum Hardware: Hashable {
        case cardReader
        case coinSlot(yen: Int)
        case tray(withChange: Bool)
        case ticketTray
    }

    let action: MachineAction
    let role: Role
    var isPrimary = false
    var isEnabled = true

    var id: MachineAction {
        self.action
    }
}

nonisolated struct MachineScreen: Hashable {
    /// The screen's own heading, in the machine's Japanese.
    var headline: String
    var info: String?
    /// A printed slip: the receipt or the ticket, shown as paper.
    var paper: String?
    var buttons: [MachineControl] = []
    var hardware: [MachineControl] = []
}

nonisolated func yen(_ amount: Int) -> String {
    "¥" + amount.formatted(.number.locale(Locale(identifier: "ja_JP")))
}

// MARK: - The machines

nonisolated enum SceneMachine: Hashable {
    case payment(Payment)
    case ageConfirm(AgeConfirm)
    case foodTicket(FoodTicket)
    case orderTablet(OrderTablet)
    case kiosk(Kiosk)

    init(kind: MachineKind, total: Int?, item: String?, menu: [MachineMenuItem]? = nil) {
        switch kind {
        case .payment: self = .payment(Payment(total: total ?? 598, item: item ?? "弁当"))
        case .ageConfirm: self = .ageConfirm(AgeConfirm())
        case .foodTicket: self = .foodTicket(FoodTicket(menu: menu ?? FoodTicket.defaultMenu))
        case .orderTablet: self = .orderTablet(OrderTablet())
        case .kiosk:
            self = .kiosk(Kiosk(item: item ?? "ハンバーガー", price: total ?? 400, options: menu ?? Kiosk.defaultOptions))
        }
    }

    var screen: MachineScreen {
        switch self {
        case let .payment(machine): machine.screen
        case let .ageConfirm(machine): machine.screen
        case let .foodTicket(machine): machine.screen
        case let .orderTablet(machine): machine.screen
        case let .kiosk(machine): machine.screen
        }
    }

    var outcome: MachineOutcome? {
        switch self {
        case let .payment(machine): machine.outcome
        case let .ageConfirm(machine): machine.outcome
        case let .foodTicket(machine): machine.outcome
        case let .orderTablet(machine): machine.outcome
        case let .kiosk(machine): machine.outcome
        }
    }

    mutating func send(_ action: MachineAction) {
        switch self {
        case var .payment(machine):
            machine.send(action)
            self = .payment(machine)
        case var .ageConfirm(machine):
            machine.send(action)
            self = .ageConfirm(machine)
        case var .foodTicket(machine):
            machine.send(action)
            self = .foodTicket(machine)
        case var .orderTablet(machine):
            machine.send(action)
            self = .orderTablet(machine)
        case var .kiosk(machine):
            machine.send(action)
            self = .kiosk(machine)
        }
    }
}

/// The customer-facing payment screen: choose a method, tap the card or feed
/// cash, pay, take the receipt. 戻る before paying returns any cash put in.
nonisolated struct Payment: Hashable {
    enum Step: Hashable {
        case choose
        case card
        case cash
        case paid(PaymentMethod)
        case done(PaymentMethod)
    }

    let total: Int
    let item: String
    private(set) var step: Step = .choose
    private(set) var inserted = 0

    var change: Int {
        max(0, self.inserted - self.total)
    }

    var outcome: MachineOutcome? {
        if case let .done(method) = self.step { return .paid(method, change: method == .cash ? self.change : 0) }
        return nil
    }

    mutating func send(_ action: MachineAction) {
        switch (self.step, action) {
        case let (.choose, .choose(method)):
            self.step = method == .card ? .card : .cash
        case (.card, .back), (.cash, .back):
            self.step = .choose
            self.inserted = 0
        case (.card, .tapCard):
            self.step = .paid(.card)
        case let (.cash, .insert(amount)) where amount > 0:
            self.inserted += amount
        case (.cash, .settle) where self.inserted >= self.total:
            self.step = .paid(.cash)
        case let (.paid(method), .take):
            self.step = .done(method)
        default:
            break
        }
    }

    var screen: MachineScreen {
        let back = MachineControl(action: .back, role: .onScreen("戻る"))
        switch self.step {
        case .choose:
            return MachineScreen(
                headline: "お支払い方法を選択してください",
                info: "お買上げ 1 点　合計 \(yen(self.total))",
                buttons: [
                    MachineControl(
                        action: .choose(.card),
                        role: .onScreen("クレジットカード"),
                        isPrimary: true
                    ),
                    MachineControl(action: .choose(.cash), role: .onScreen("現金"))
                ]
            )
        case .card:
            return MachineScreen(
                headline: "カードをかざしてください",
                info: "お支払い金額 \(yen(self.total))",
                buttons: [back],
                hardware: [MachineControl(action: .tapCard, role: .hardware(.cardReader))]
            )
        case .cash:
            let short = self.total - self.inserted
            let balance = short > 0 ? "不足 \(yen(short))" : "おつり \(yen(-short))"
            return MachineScreen(
                headline: "現金を入れてください",
                info: "合計 \(yen(self.total))　お預り \(yen(self.inserted))\n\(balance)",
                buttons: (short <= 0
                    ? [MachineControl(action: .settle, role: .onScreen("精算する"), isPrimary: true)]
                    : []) + [back],
                hardware: [100, 500, 1000].map {
                    MachineControl(action: .insert(yen: $0), role: .hardware(.coinSlot(yen: $0)))
                }
            )
        case let .paid(method):
            let cash = method == .cash
            return MachineScreen(
                headline: cash ? "おつりとレシートをお取りください" : "レシートをお取りください",
                paper: "お買上げ明細\n\(self.item)　\(yen(self.total))\n"
                    + (cash ? "お預り　\(yen(self.inserted))\nおつり　\(yen(self.change))" : "クレジット"),
                hardware: [MachineControl(action: .take, role: .hardware(.tray(withChange: cash)))]
            )
        case .done:
            return MachineScreen(headline: "ありがとうございました", info: "お会計が完了しました")
        }
    }
}

/// The age check shown when the basket has alcohol.
nonisolated struct AgeConfirm: Hashable {
    private(set) var answer: AgeAnswer?

    var outcome: MachineOutcome? {
        self.answer.map { .age($0) }
    }

    mutating func send(_ action: MachineAction) {
        guard self.answer == nil, case let .answerAge(answer) = action else { return }
        self.answer = answer
    }

    var screen: MachineScreen {
        switch self.answer {
        case nil:
            MachineScreen(
                headline: "年齢確認",
                info: "お酒をご購入のお客様へ\n20歳以上ですか？",
                buttons: [
                    MachineControl(action: .answerAge(.yes), role: .onScreen("はい"), isPrimary: true),
                    MachineControl(action: .answerAge(.no), role: .onScreen("いいえ")),
                    MachineControl(action: .answerAge(.cancel), role: .onScreen("取消"))
                ]
            )
        case .yes: MachineScreen(headline: "年齢確認が完了しました", info: "お会計へお進みください")
        case .no: MachineScreen(headline: "係員が確認します", info: "この商品はお会計を保留しています")
        case .cancel: MachineScreen(headline: "年齢確認を取り消しました", info: "係員にお声がけください")
        }
    }
}

/// The 食券機 at a ramen shop's door: pick an item, confirm, feed ¥1,000
/// notes, take the ticket and change. The menu comes from the scene.
nonisolated struct FoodTicket: Hashable {
    static let defaultMenu = [
        MachineMenuItem(id: "shoyu", name: "醤油ラーメン", price: 900),
        MachineMenuItem(id: "miso", name: "味噌ラーメン", price: 980),
        MachineMenuItem(id: "gyoza", name: "餃子", price: 380)
    ]

    enum Step: Hashable {
        case choose
        case confirm(Int)
        case cash(Int)
        case issued(Int)
        case done(Int)
    }

    let menu: [MachineMenuItem]
    private(set) var step: Step = .choose
    private(set) var inserted = 0

    init(menu: [MachineMenuItem]) {
        self.menu = menu.isEmpty ? Self.defaultMenu : menu
    }

    var outcome: MachineOutcome? {
        guard case let .done(index) = self.step else { return nil }
        let item = self.menu[index]
        return .ticket(item: item.id, change: self.inserted - item.price)
    }

    mutating func send(_ action: MachineAction) {
        switch (self.step, action) {
        case let (.choose, .pickDish(index)) where self.menu.indices.contains(index):
            self.step = .confirm(index)
        case (.confirm, .back):
            self.step = .choose
        case let (.confirm(index), .payDishInCash):
            self.step = .cash(index)
        case let (.cash(index), .insert(amount)) where amount > 0 && self.inserted < self.menu[index].price:
            self.inserted += amount
        case let (.cash(index), .issueTicket) where self.inserted >= self.menu[index].price:
            self.step = .issued(index)
        case let (.issued(index), .take):
            self.step = .done(index)
        default:
            break
        }
    }

    var screen: MachineScreen {
        switch self.step {
        case .choose:
            return MachineScreen(
                headline: "食券をお選びください",
                info: "メニュー",
                buttons: self.menu.enumerated().map { index, item in
                    MachineControl(action: .pickDish(index), role: .onScreen("\(item.name)　\(yen(item.price))"))
                }
            )
        case let .confirm(index):
            let item = self.menu[index]
            return MachineScreen(
                headline: "ご購入内容の確認",
                info: "\(item.name) × 1　\(yen(item.price))",
                buttons: [
                    MachineControl(action: .payDishInCash, role: .onScreen("現金で支払う"), isPrimary: true),
                    MachineControl(action: .back, role: .onScreen("戻る"))
                ]
            )
        case let .cash(index):
            let price = self.menu[index].price
            let enough = self.inserted >= price
            return MachineScreen(
                headline: "現金を入れてください",
                info: "合計 \(yen(price))　お預り \(yen(self.inserted))"
                    + (enough ? "\nおつり \(yen(self.inserted - price))" : "\n不足 \(yen(price - self.inserted))"),
                buttons: enough ? [MachineControl(action: .issueTicket, role: .onScreen("発券する"), isPrimary: true)] : [],
                hardware: enough ? [] : [MachineControl(
                    action: .insert(yen: 1000),
                    role: .hardware(.coinSlot(yen: 1000))
                )]
            )
        case let .issued(index):
            let item = self.menu[index]
            return MachineScreen(
                headline: "食券とおつりをお取りください",
                paper: "食券　No. 023\n\(item.name)　\(yen(item.price))\nおつり　\(yen(self.inserted - item.price))",
                hardware: [MachineControl(action: .take, role: .hardware(.ticketTray))]
            )
        case let .done(index):
            return MachineScreen(headline: "食券を店員にお渡しください", info: "\(self.menu[index].name) × 1")
        }
    }
}

/// A self-order kiosk at a fast-food counter: it offers to make the item a
/// set, shows the price difference, takes the order and gives a number.
nonisolated struct Kiosk: Hashable {
    static let defaultOptions = [
        MachineMenuItem(id: "set", name: "セットにする", price: 300),
        MachineMenuItem(id: "single", name: "単品のまま", price: 0)
    ]

    enum Step: Hashable {
        case offer
        case confirm(Int)
        case placed(Int)
    }

    let item: String
    let price: Int
    let options: [MachineMenuItem]
    private(set) var step: Step = .offer

    init(item: String, price: Int, options: [MachineMenuItem]) {
        self.item = item
        self.price = price
        self.options = options.isEmpty ? Self.defaultOptions : options
    }

    private func total(_ index: Int) -> Int {
        self.price + self.options[index].price
    }

    var outcome: MachineOutcome? {
        guard case let .placed(index) = self.step else { return nil }
        return .kioskOrder(option: self.options[index].id, total: self.total(index))
    }

    mutating func send(_ action: MachineAction) {
        switch (self.step, action) {
        case let (.offer, .pickOption(index)) where self.options.indices.contains(index):
            self.step = .confirm(index)
        case (.confirm, .back):
            self.step = .offer
        case let (.confirm(index), .confirmOrder):
            self.step = .placed(index)
        default:
            break
        }
    }

    var screen: MachineScreen {
        switch self.step {
        case .offer:
            return MachineScreen(
                headline: "セットにしますか？",
                info: "\(self.item)　\(yen(self.price))",
                buttons: self.options.enumerated().map { index, option in
                    let label = option.price > 0 ? "\(option.name)　+\(yen(option.price))" : option.name
                    return MachineControl(action: .pickOption(index), role: .onScreen(label))
                }
            )
        case let .confirm(index):
            let option = self.options[index]
            let line = option.price > 0 ? "\(self.item)（\(option.name)）" : self.item
            return MachineScreen(
                headline: "ご注文内容の確認",
                info: "\(line)\n合計 \(yen(self.total(index)))",
                buttons: [
                    MachineControl(action: .confirmOrder, role: .onScreen("注文する"), isPrimary: true),
                    MachineControl(action: .back, role: .onScreen("戻る"))
                ]
            )
        case let .placed(index):
            return MachineScreen(
                headline: "ご注文ありがとうございます",
                info: "番号をお呼びするまでお待ちください",
                paper: "受付番号　021\n合計　\(yen(self.total(index)))"
            )
        }
    }
}

/// The table tablet: pick a category and a dish, set how many, confirm, send,
/// then look at the order history.
nonisolated struct OrderTablet: Hashable {
    static let items: [TabletCategory: (name: String, price: Int)] = [
        .noodles: ("きつねうどん", 680),
        .drinks: ("アイス烏龍茶", 280)
    ]

    enum Step: Hashable {
        case browse
        case cart
        case confirm
        case sent
        case history
    }

    private(set) var step: Step = .browse
    private(set) var category: TabletCategory = .noodles
    private(set) var cartCategory: TabletCategory?
    private(set) var quantity = 0

    static let maxCount = 9

    private var cartItem: (name: String, price: Int)? {
        self.cartCategory.flatMap { Self.items[$0] }
    }

    var outcome: MachineOutcome? {
        guard self.step == .sent || self.step == .history, let item = self.cartItem else { return nil }
        return .ordered(item: item.name, count: self.quantity, total: item.price * self.quantity)
    }

    mutating func send(_ action: MachineAction) {
        switch (self.step, action) {
        case let (.browse, .pickCategory(category)):
            self.category = category
        case (.browse, .addToCart):
            self.cartCategory = self.category
            self.quantity = 1
            self.step = .cart
        case (.cart, .more) where self.quantity < Self.maxCount:
            self.quantity += 1
        case (.cart, .fewer):
            self.quantity -= 1
            if self.quantity <= 0 {
                self.cartCategory = nil
                self.step = .browse
            }
        case (.cart, .review):
            self.step = .confirm
        case (.confirm, .back):
            self.step = .cart
        case (.confirm, .placeOrder):
            self.step = .sent
        case (.sent, .showHistory):
            self.step = .history
        default:
            break
        }
    }

    var screen: MachineScreen {
        switch self.step {
        case .browse:
            let item = Self.items[self.category] ?? ("", 0)
            return MachineScreen(
                headline: "メニュー",
                info: "\(self.category.rawValue)　／　注文かご \(self.quantity) 点",
                buttons: TabletCategory.allCases.map {
                    MachineControl(
                        action: .pickCategory($0),
                        role: .onScreen($0.rawValue),
                        isPrimary: $0 == self.category
                    )
                } + [MachineControl(
                    action: .addToCart,
                    role: .onScreen("\(item.name)　\(yen(item.price))")
                )]
            )
        case .cart:
            let item = self.cartItem ?? ("", 0)
            return MachineScreen(
                headline: "注文かご",
                info: "\(item.name) × \(self.quantity)　小計 \(yen(item.price * self.quantity))",
                buttons: [
                    MachineControl(action: .fewer, role: .onScreen("数量を減らす")),
                    MachineControl(
                        action: .more,
                        role: .onScreen("数量を増やす"),
                        isEnabled: self.quantity < Self.maxCount
                    ),
                    MachineControl(action: .review, role: .onScreen("注文内容を確認"), isPrimary: true)
                ]
            )
        case .confirm:
            let item = self.cartItem ?? ("", 0)
            return MachineScreen(
                headline: "この内容で注文しますか？",
                info: "\(item.name) × \(self.quantity)　\(yen(item.price * self.quantity))",
                buttons: [
                    MachineControl(action: .placeOrder, role: .onScreen("注文する"), isPrimary: true),
                    MachineControl(action: .back, role: .onScreen("戻る"))
                ]
            )
        case .sent, .history:
            let item = self.cartItem ?? ("", 0)
            return MachineScreen(
                headline: self.step == .sent ? "ご注文を受け付けました" : "注文履歴",
                info: "注文番号 001\n\(item.name) × \(self.quantity)　\(yen(item.price * self.quantity))",
                buttons: self.step == .sent ? [MachineControl(
                    action: .showHistory,
                    role: .onScreen("注文履歴を見る")
                )] : []
            )
        }
    }
}

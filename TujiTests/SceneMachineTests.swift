// The four machines, against the handoff's acceptance list
// (docs/SCENE_PRACTICE_DEV_HANDOFF.md, 交付驗收).

import Testing
@testable import Tuji

struct SceneMachineTests {
    private func payment() -> SceneMachine {
        SceneMachine(kind: .payment, total: 598, item: "弁当")
    }

    @Test
    func cashShortOfTheTotalShowsTheShortfallAndCannotBeSettled() {
        var machine = self.payment()
        machine.send(.choose(.cash))
        machine.send(.insert(yen: 500))
        #expect(machine.screen.info?.contains("不足 ¥98") == true)
        #expect(!machine.screen.buttons.contains { $0.action == .settle })
        machine.send(.settle)
        #expect(machine.outcome == nil)
    }

    @Test
    func aThousandYenForFiveNinetyEightGivesFourOhTwoChange() {
        var machine = self.payment()
        machine.send(.choose(.cash))
        machine.send(.insert(yen: 1000))
        #expect(machine.screen.info?.contains("おつり ¥402") == true)
        machine.send(.settle)
        #expect(machine.screen.paper?.contains("おつり　¥402") == true)
        machine.send(.take)
        #expect(machine.outcome == .paid(.cash, change: 402))
    }

    @Test
    func goingBackFromCashReturnsTheMoneyAndCardStillPays() {
        var machine = self.payment()
        machine.send(.choose(.cash))
        machine.send(.insert(yen: 500))
        machine.send(.back)
        #expect(machine.screen.headline == "お支払い方法を選択してください")
        machine.send(.choose(.card))
        machine.send(.tapCard)
        machine.send(.take)
        #expect(machine.outcome == .paid(.card, change: 0))
    }

    @Test
    func tappingTwiceOrTakingTwiceChangesNothing() {
        var machine = self.payment()
        machine.send(.choose(.card))
        machine.send(.tapCard)
        machine.send(.tapCard)
        machine.send(.take)
        let finished = machine
        machine.send(.take)
        machine.send(.back)
        machine.send(.choose(.cash))
        #expect(machine == finished)
    }

    @Test(arguments: [AgeAnswer.yes, .no, .cancel])
    func eachAgeAnswerEndsOnItsOwnScreen(answer: AgeAnswer) {
        var machine = SceneMachine(kind: .ageConfirm, total: nil, item: nil)
        machine.send(.answerAge(answer))
        machine.send(.answerAge(.yes))
        #expect(machine.outcome == .age(answer))
        let titles: [AgeAnswer: String] = [.yes: "年齢確認が完了しました", .no: "係員が確認します", .cancel: "年齢確認を取り消しました"]
        #expect(machine.screen.headline == titles[answer])
    }

    @Test
    func theTicketShowsTheDishPickedAndItsChange() {
        var machine = SceneMachine(kind: .foodTicket, total: nil, item: nil)
        machine.send(.pickDish(1))
        machine.send(.back)
        machine.send(.pickDish(0))
        machine.send(.payDishInCash)
        machine.send(.issueTicket)
        #expect(machine.outcome == nil)
        machine.send(.insert(yen: 1000))
        machine.send(.insert(yen: 1000))
        machine.send(.issueTicket)
        #expect(machine.screen.paper?.contains("醤油ラーメン　¥900") == true)
        machine.send(.take)
        #expect(machine.outcome == .ticket(item: "shoyu", change: 100))
    }

    @Test
    func theTabletRecordsTheConfirmedCountAndTotal() {
        var machine = SceneMachine(kind: .orderTablet, total: nil, item: nil)
        machine.send(.pickCategory(.drinks))
        machine.send(.addToCart)
        machine.send(.more)
        machine.send(.more)
        machine.send(.fewer)
        machine.send(.review)
        #expect(machine.screen.info == "アイス烏龍茶 × 2　¥560")
        machine.send(.placeOrder)
        machine.send(.placeOrder)
        machine.send(.showHistory)
        #expect(machine.outcome == .ordered(item: "アイス烏龍茶", count: 2, total: 560))
        #expect(machine.screen.info?.contains("アイス烏龍茶 × 2　¥560") == true)
    }

    @Test
    func emptyingTheCartGoesBackToTheMenu() {
        var machine = SceneMachine(kind: .orderTablet, total: nil, item: nil)
        machine.send(.addToCart)
        machine.send(.fewer)
        #expect(machine.screen.headline == "メニュー")
        #expect(machine.outcome == nil)
    }

    @Test
    func theKioskShowsThePriceDifferenceAndANumber() {
        var machine = SceneMachine(kind: .kiosk, total: 400, item: "ハンバーガー", menu: [
            MachineMenuItem(id: "set", name: "セットにする", price: 300),
            MachineMenuItem(id: "single", name: "単品のまま", price: 0)
        ])
        machine.send(.pickOption(0))
        #expect(machine.screen.info == "ハンバーガー（セットにする）\n合計 ¥700")
        machine.send(.back)
        machine.send(.pickOption(1))
        #expect(machine.screen.info == "ハンバーガー\n合計 ¥400")
        machine.send(.confirmOrder)
        machine.send(.confirmOrder)
        #expect(machine.outcome == .kioskOrder(option: "single", total: 400))
        #expect(machine.screen.paper?.contains("受付番号　021") == true)
    }

    @Test
    func aTicketMachineSellsTheScenesOwnMenu() {
        var machine = SceneMachine(kind: .foodTicket, total: nil, item: nil, menu: [
            MachineMenuItem(id: "oomori", name: "大盛", price: 100),
            MachineMenuItem(id: "kaedama", name: "替玉", price: 150)
        ])
        #expect(machine.screen.buttons.map(\.role) == [.onScreen("大盛　¥100"), .onScreen("替玉　¥150")])
        machine.send(.pickDish(0))
        machine.send(.payDishInCash)
        machine.send(.insert(yen: 1000))
        machine.send(.issueTicket)
        machine.send(.take)
        #expect(machine.outcome == .ticket(item: "oomori", change: 900))
        let spec = StageMachine(kind: .foodTicket, total: nil, item: nil, menu: nil, brand: nil, expect: "oomori")
        #expect(spec.fits(.ticket(item: "oomori", change: 900)))
        #expect(!spec.fits(.ticket(item: "kaedama", change: 850)))
    }
}

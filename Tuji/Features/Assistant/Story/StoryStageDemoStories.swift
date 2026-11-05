import Foundation

#if DEBUG
/// Local fixtures exercise every region and prop without a generated story or a charge.
enum StoryStageDemoStories {
    private struct Content {
        let heading: String
        let intro: String
        let segments: [Story.Segment]
    }

    static func story(sceneId: String) -> Story? {
        let content: Content
        switch sceneId {
        case "office": content = self.office
        case "restaurant": content = self.restaurant
        case "station": content = self.station
        case "home": content = self.home
        default: return nil
        }
        return Story(title: content.heading, intro: content.intro, segments: content.segments, wordNotes: nil)
    }

    private static func line(
        _ speaker: Story.Segment.Speaker, _ text: String, _ translation: String?,
        _ area: String, _ action: String, ruby: [(String, String?)]? = nil
    )
        -> Story.Segment
    {
        .init(
            speaker: speaker, text: text, furigana: ruby?.map { FuriganaSegment(text: $0.0, ruby: $0.1) }, reading: nil,
            translation: translation, wordIds: [], stage: .init(areaId: area, moiraAction: action)
        )
    }

    private static let office = Content(heading: "和Moira一起準備會議", intro: "你來到辦公室，Moira正準備下午開會要用的資料。", segments: [
        line(.narrator, "Moira在工作桌旁拿起一份文件，仔細閱讀。", nil, "desk", "read_document"),
        line(.cat, "書類を一緒に確認しましょう。", "我們一起確認文件吧。", "desk", "read_document", ruby: [
            ("書類", "しょるい"), ("を", nil), ("一緒", "いっしょ"),
            ("に", nil), ("確認", "かくにん"), ("しましょう。", nil)
        ]),
        line(.you, "はい、ここを見てください。", "好，請看看這裡。", "desk", "listen"),
        line(.narrator, "Moira放下文件，打開筆記型電腦，開始輸入會議紀錄。", nil, "desk", "use_laptop"),
        line(.cat, "これで準備ができました。", "這樣就準備好了。", "desk", "use_laptop"),
        line(.narrator, "Moira關上電腦，和你走進會議室。", nil, "meeting", "point"),
        line(.cat, "こちらに座りましょう。", "我們坐這裡吧。", "meeting", "point"),
        line(.narrator, "會議結束後，你們來到休息室，聊起今天的工作。", nil, "breakroom", "nod"),
        line(.cat, "今日もお疲れさまでした。", "今天也辛苦了。", "breakroom", "goodbye")
    ])

    private static let restaurant = Content(heading: "和Moira一起吃午餐", intro: "你和Moira來到一間溫暖的小餐廳，準備吃午餐。", segments: [
        line(.cat, "ここに入りましょう。", "我們進去吧。", "entrance", "greet"),
        line(.narrator, "你們坐到餐桌旁，Moira拿起菜單，開始選午餐。", nil, "dining", "read_menu"),
        line(.cat, "このメニューを見てください。", "請看看這份菜單。", "dining", "read_menu", ruby: [
            ("このメニューを", nil), ("見", "み"), ("てください。", nil)
        ]),
        line(.you, "どれがおすすめですか。", "你推薦哪一道？", "dining", "listen"),
        line(.narrator, "點完餐後，Moira放下菜單，雙手捧起白色的杯子。", nil, "dining", "hold_cup"),
        line(.cat, "温かくて、おいしいですね。", "暖暖的，真好喝。", "dining", "hold_cup"),
        line(.narrator, "吃完午餐，Moira放好杯子，你們走到收銀台結帳。", nil, "checkout", "nod"),
        line(.cat, "また一緒に来ましょう。", "下次再一起來吧。", "checkout", "goodbye")
    ])

    private static let station = Content(heading: "和Moira一起搭電車", intro: "你和Moira在車站碰面，準備搭電車去附近的小鎮。", segments: [
        line(.narrator, "在車站大廳，Moira展開紙本路線圖，確認要搭的路線。", nil, "concourse", "check_map"),
        line(.cat, "地図で行き方を確認しましょう。", "我們用地圖確認路線吧。", "concourse", "check_map", ruby: [
            ("地図", "ちず"), ("で", nil), ("行", "い"),
            ("き", nil), ("方", "かた"), ("を", nil),
            ("確認", "かくにん"), ("しましょう。", nil)
        ]),
        line(.you, "この電車でいいですか。", "搭這班電車可以嗎？", "concourse", "listen"),
        line(.narrator, "Moira收起地圖，拿著自己的紙本車票，和你走到驗票口。", nil, "gate", "hold_ticket"),
        line(.cat, "切符を用意しました。", "我的車票準備好了。", "gate", "hold_ticket"),
        line(.narrator, "通過驗票口後，Moira收好車票，你們走到月台等車。", nil, "platform", "point"),
        line(.cat, "ここで待ちましょう。", "我們在這裡等吧。", "platform", "nod")
    ])

    private static let home = Content(heading: "和Moira在家度過午後", intro: "安靜的午後，你和Moira在家裡慢慢聊天。", segments: [
        line(.narrator, "在客廳裡，Moira拿著一本綠色封面的書，讀得很專心。", nil, "living", "read_book"),
        line(.cat, "この本はとても面白いです。", "這本書非常有趣。", "living", "read_book", ruby: [
            ("この", nil), ("本", "ほん"), ("はとても", nil),
            ("面白", "おもしろ"), ("いです。", nil)
        ]),
        line(.you, "あとで読んでもいいですか。", "待會兒我也可以讀嗎？", "living", "listen"),
        line(.narrator, "Moira把書放回書架，和你走進廚房，捧起一個白色杯子。", nil, "kitchen", "hold_cup"),
        line(.cat, "少し休みましょう。", "我們休息一下吧。", "kitchen", "hold_cup"),
        line(.narrator, "喝完茶，Moira放下杯子，走到臥室整理床邊的小桌子。", nil, "bedroom", "nod"),
        line(.cat, "また明日、お話ししましょう。", "明天再一起聊天吧。", "bedroom", "goodbye")
    ])
}
#endif

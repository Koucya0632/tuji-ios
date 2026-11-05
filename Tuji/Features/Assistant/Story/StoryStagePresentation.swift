import Foundation

/// The only mapping from optional story hints to the artwork bundled for a place.
/// Cues are snapshots, so replay and streamed completion resolve identically.
struct StoryStagePresentation: Equatable {
    enum Scene: String, CaseIterable {
        case supermarket, office, restaurant, station, home

        var areas: [Area] {
            switch self {
            case .supermarket: [.general, .entrance, .produce, .checkout]
            case .office: [.general, .desk, .meeting, .breakroom]
            case .restaurant: [.general, .entrance, .dining, .checkout]
            case .station: [.general, .concourse, .gate, .platform]
            case .home: [.general, .living, .kitchen, .bedroom]
            }
        }

        var actions: [Action] {
            let props: [Action] = switch self {
            case .supermarket: [.holdApple, .carryBag]
            case .office: [.readDocument, .useLaptop]
            case .restaurant: [.readMenu, .holdCup]
            case .station: [.holdTicket, .checkMap]
            case .home: [.readBook, .holdCup]
            }
            return [.greet, .listen, .think, .confused, .surprised, .point, .nod, .goodbye] + props
        }

        var label: String {
            switch self {
            case .supermarket: tujiLocalized("超市")
            case .office: tujiLocalized("辦公室")
            case .restaurant: tujiLocalized("餐廳")
            case .station: tujiLocalized("車站")
            case .home: tujiLocalized("家裡")
            }
        }
    }

    enum Area: String, CaseIterable {
        case general, entrance, produce, checkout, desk, meeting, breakroom
        case dining, concourse, gate, platform, living, kitchen, bedroom

        var label: String {
            switch self {
            case .general: ""
            case .entrance: tujiLocalized("入口")
            case .produce: tujiLocalized("水果區")
            case .checkout: tujiLocalized("收銀台")
            case .desk: tujiLocalized("工作區")
            case .meeting: tujiLocalized("會議室")
            case .breakroom: tujiLocalized("休息室")
            case .dining: tujiLocalized("用餐區")
            case .concourse: tujiLocalized("車站大廳")
            case .gate: tujiLocalized("驗票口")
            case .platform: tujiLocalized("月台")
            case .living: tujiLocalized("客廳")
            case .kitchen: tujiLocalized("廚房")
            case .bedroom: tujiLocalized("臥室")
            }
        }
    }

    enum Action: String, CaseIterable {
        case greet, listen, think, confused, surprised, point, nod, goodbye
        case holdApple = "hold_apple"
        case carryBag = "carry_bag"
        case readDocument = "read_document"
        case useLaptop = "use_laptop"
        case readMenu = "read_menu"
        case holdCup = "hold_cup"
        case holdTicket = "hold_ticket"
        case checkMap = "check_map"
        case readBook = "read_book"

        var imageName: String {
            "story-moira-\(self.rawValue)"
        }
    }

    let scene: Scene
    let area: Area
    let action: Action

    var backgroundImageName: String {
        "story-\(self.scene.rawValue)-\(self.area.rawValue)"
    }

    var label: String {
        self.area == .general ? self.scene.label : "\(self.scene.label) · \(self.area.label)"
    }

    init(scene: Scene, segment: Story.Segment?) {
        self.scene = scene
        guard let segment else {
            self.area = .general
            self.action = .greet
            return
        }
        let area = segment.stage?.areaId.flatMap(Area.init(rawValue:))
        self.area = area.flatMap { scene.areas.contains($0) ? $0 : nil } ?? .general
        let action = segment.stage?.moiraAction.flatMap(Action.init(rawValue:))
        self.action = action.flatMap { scene.actions.contains($0) ? $0 : nil }
            ?? (segment.speaker == .you ? .listen : .think)
    }
}

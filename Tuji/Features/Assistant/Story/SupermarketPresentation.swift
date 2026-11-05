import Foundation

/// The single mapping from optional story hints to bundled supermarket art.
/// A cue is a snapshot, not a transition: replay and streamed completion agree.
struct SupermarketPresentation: Equatable {
    enum Area: String, CaseIterable {
        case general, entrance, produce, checkout

        var imageName: String {
            "story-supermarket-\(self.rawValue)"
        }

        var label: String {
            switch self {
            case .general: tujiLocalized("超市")
            case .entrance: tujiLocalized("超市 · 入口")
            case .produce: tujiLocalized("超市 · 水果區")
            case .checkout: tujiLocalized("超市 · 收銀台")
            }
        }
    }

    enum Action: String, CaseIterable {
        case greet, listen, think, confused, surprised, point, nod, goodbye
        case holdApple = "hold_apple"
        case carryBag = "carry_bag"

        var imageName: String {
            "story-moira-\(self.rawValue)"
        }
    }

    let area: Area
    let action: Action

    init(segment: Story.Segment?) {
        guard let segment else {
            self.area = .general
            self.action = .greet
            return
        }
        self.area = segment.stage?.areaId.flatMap(Area.init(rawValue:)) ?? .general
        self.action = segment.stage?.moiraAction.flatMap(Action.init(rawValue:))
            ?? (segment.speaker == .you ? .listen : .think)
    }
}

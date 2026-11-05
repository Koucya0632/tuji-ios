// Generated from measured alpha bounds of the bundled sprites. See docs/story-stage/assets.json.
import Foundation

enum StorySpriteMetrics {
    struct Bounds {
        let left: CGFloat
        let top: CGFloat
        let right: CGFloat
        let bottom: CGFloat
    }

    static func bounds(for action: SupermarketPresentation.Action) -> Bounds {
        switch action {
        case .listen: Bounds(left: 0.191388, top: 0.054226, right: 0.815789, bottom: 0.945774)
        case .greet: Bounds(left: 0.189793, top: 0.055821, right: 0.818182, bottom: 0.945774)
        case .think: Bounds(left: 0.189793, top: 0.050239, right: 0.818182, bottom: 0.947368)
        case .confused: Bounds(left: 0.189793, top: 0.039872, right: 0.813397, bottom: 0.946571)
        case .surprised: Bounds(left: 0.191388, top: 0.053429, right: 0.812600, bottom: 0.939394)
        case .point: Bounds(left: 0.185008, top: 0.054226, right: 0.885167, bottom: 0.945774)
        case .nod: Bounds(left: 0.190590, top: 0.088517, right: 0.801435, bottom: 0.946571)
        case .goodbye: Bounds(left: 0.142743, top: 0.054226, right: 0.874801, bottom: 0.945774)
        case .holdApple: Bounds(left: 0.190590, top: 0.053429, right: 0.802233, bottom: 0.938596)
        case .carryBag: Bounds(left: 0.181818, top: 0.055821, right: 0.847687, bottom: 0.943381)
        }
    }
}

// The photo a staged 問句 happens in, with its props placed on it.
//
// The photo fills the space above the panel. How much of it shows depends on
// the screen and on how tall the panel is (larger text makes it taller), so
// each background names the point that must stay in view (the counter, the
// table) and the spots props sit on, both as fractions of the photo. Props
// are placed in the photo's own coordinates, so a menu stays on the table
// however the photo is cropped.

import SwiftUI

/// Where things are in one background photo, as fractions of its size.
struct StageBackdrop {
    /// The point kept in view when the photo is cropped.
    let focus: UnitPoint
    /// Where props stand, in order: the first prop takes the first spot.
    let spots: [UnitPoint]
    /// A prop's width as a fraction of the photo's width.
    let propWidth: CGFloat

    static func named(_ name: String) -> StageBackdrop {
        self.table[name] ?? StageBackdrop(focus: .center, spots: [UnitPoint(x: 0.5, y: 0.8)], propWidth: 0.25)
    }

    private static let table: [String: StageBackdrop] = [
        "bg-konbini-register": StageBackdrop(
            focus: UnitPoint(x: 0.5, y: 0.66),
            spots: [UnitPoint(x: 0.43, y: 0.71), UnitPoint(x: 0.76, y: 0.8), UnitPoint(x: 0.17, y: 0.76)],
            propWidth: 0.28
        ),
        "story-restaurant-dining": StageBackdrop(
            focus: UnitPoint(x: 0.74, y: 0.45),
            spots: [UnitPoint(x: 0.8, y: 0.425)],
            propWidth: 0.12
        ),
        "story-restaurant-checkout": StageBackdrop(
            focus: UnitPoint(x: 0.8, y: 0.45),
            spots: [UnitPoint(x: 0.86, y: 0.392)],
            propWidth: 0.075
        ),
        "story-restaurant-entrance": StageBackdrop(
            focus: UnitPoint(x: 0.5, y: 0.45),
            spots: [UnitPoint(x: 0.83, y: 0.41)],
            propWidth: 0.1
        )
    ]
}

struct StageBackdropView: View {
    let background: String
    let props: [String]

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(
                container: geo.size,
                image: UIImage(named: self.background)?.size ?? CGSize(width: 2, height: 3),
                backdrop: .named(self.background)
            )
            ZStack(alignment: .topLeading) {
                Image(self.background)
                    .resizable()
                    .frame(width: layout.drawn.width, height: layout.drawn.height)
                    .offset(x: layout.origin.x, y: layout.origin.y)
                    .accessibilityHidden(true)
                ForEach(Array(self.props.enumerated()), id: \.element) { index, name in
                    let spot = layout.spot(index)
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(width: layout.propWidth)
                        .shadow(color: .tujiInk.opacity(0.25), radius: 4, y: 2)
                        .position(spot)
                        .accessibilityLabel(Text(StageProp.label(name)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// The photo scaled to fill the container, shifted so its focus point
    /// sits as close to the container's middle as the photo's edges allow.
    struct Layout {
        let drawn: CGSize
        let origin: CGPoint
        let propWidth: CGFloat
        private let spots: [UnitPoint]

        init(container: CGSize, image: CGSize, backdrop: StageBackdrop) {
            let scale = max(container.width / max(image.width, 1), container.height / max(image.height, 1))
            self.drawn = CGSize(width: image.width * scale, height: image.height * scale)
            func place(_ length: CGFloat, _ drawn: CGFloat, _ focus: CGFloat) -> CGFloat {
                min(0, max(length - drawn, length / 2 - focus * drawn))
            }
            self.origin = CGPoint(
                x: place(container.width, self.drawn.width, backdrop.focus.x),
                y: place(container.height, self.drawn.height, backdrop.focus.y)
            )
            self.propWidth = min(160, backdrop.propWidth * self.drawn.width)
            self.spots = backdrop.spots
        }

        func spot(_ index: Int) -> CGPoint {
            let unit = self.spots.isEmpty ? UnitPoint(x: 0.5, y: 0.8) : self.spots[min(index, self.spots.count - 1)]
            return CGPoint(x: self.origin.x + unit.x * self.drawn.width, y: self.origin.y + unit.y * self.drawn.height)
        }
    }
}

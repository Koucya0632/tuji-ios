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
    /// Where a paper slip (`StageCard`) sits.
    var cardSpot = UnitPoint(x: 0.5, y: 0.72)

    static func named(_ name: String) -> StageBackdrop {
        self.table[name] ?? StageBackdrop(focus: .center, spots: [UnitPoint(x: 0.5, y: 0.8)], propWidth: 0.25)
    }

    /// Wave 2 photos: the focus is the counter or machine the scene happens
    /// at, and the card sits where the materials table puts it.
    private static func counter(_ x: CGFloat, _ y: CGFloat) -> StageBackdrop {
        StageBackdrop(
            focus: UnitPoint(x: x, y: y - 0.06),
            spots: [UnitPoint(x: x, y: y)],
            propWidth: 0.24,
            cardSpot: UnitPoint(x: x, y: y)
        )
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
        "scene-bg-ramen-shop": counter(0.68, 0.74),
        "scene-bg-hotel-check-in": counter(0.53, 0.58),
        "scene-bg-taxi": counter(0.5, 0.78),
        "scene-bg-fast-food": counter(0.72, 0.75),
        "scene-bg-ryokan": counter(0.52, 0.67),
        "scene-bg-cafe": counter(0.5, 0.68),
        "scene-bg-izakaya": counter(0.49, 0.68),
        "scene-bg-conveyor-sushi": counter(0.48, 0.72),
        "scene-bg-station-ticket-office": counter(0.49, 0.63),
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
    var card: StageCard?

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
                if let card = self.card {
                    StageCardView(card: card)
                        .frame(width: min(210, geo.size.width * 0.55))
                        .position(layout.point(StageBackdrop.named(self.background).cardSpot))
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

        func point(_ unit: UnitPoint) -> CGPoint {
            CGPoint(x: self.origin.x + unit.x * self.drawn.width, y: self.origin.y + unit.y * self.drawn.height)
        }

        func spot(_ index: Int) -> CGPoint {
            let unit = self.spots.isEmpty ? UnitPoint(x: 0.5, y: 0.8) : self.spots[min(index, self.spots.count - 1)]
            return CGPoint(x: self.origin.x + unit.x * self.drawn.width, y: self.origin.y + unit.y * self.drawn.height)
        }
    }
}

/// A paper slip on the counter. The Japanese is the paper's own.
struct StageCardView: View {
    let card: StageCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: self.card.title)
                .font(.tujiLabel)
                .foregroundStyle(.tujiInk2)
            ForEach(self.card.lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.tujiBodySm(.strong))
                    .monospacedDigit()
                    .foregroundStyle(.tujiInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tujiPaper)
        .overlay(Rectangle().strokeBorder(.tujiRule, lineWidth: 1))
        .shadow(color: .tujiInk.opacity(0.25), radius: 5, y: 2)
        .environment(\.locale, Locale(identifier: "ja"))
        .accessibilityElement(children: .combine)
    }
}

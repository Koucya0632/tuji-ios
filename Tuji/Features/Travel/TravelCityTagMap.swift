// The 2026-11 city map and the cards under it (TravelCityView).

import SwiftUI

/// The 2026-11 city map: every marker on its true place, a tag with the
/// spot's number and name joined to it by a line. The server placed the tags
/// so none covers another (tuji-web lib/travel/japan/layout.ts); the type is
/// fixed in size for the same reason.
struct TravelCityTagMap: View {
    let city: TravelCity
    /// The city's region colour, washed into the paper as the ground.
    let tone: Color
    var photographed: Set<String> = []

    @Environment(\.presentPaywall) private var presentPaywall

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for shape in self.city.shapes {
                        Self.draw(shape, in: &context, size: size)
                    }
                    for spot in self.city.spots {
                        guard let pin = spot.pin, let tag = spot.tag else { continue }
                        var line = Path()
                        line.move(to: Self.place(pin, size))
                        line.addLine(to: Self.place(tag, size))
                        context.stroke(line, with: .color(spot.open ? .tujiInk : .tujiInk3), lineWidth: 1.5)
                    }
                    for spot in self.city.spots {
                        guard let pin = spot.pin else { continue }
                        let c = Self.place(pin, size)
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: c.x, y: c.y - 7.5))
                        diamond.addLine(to: CGPoint(x: c.x + 7.5, y: c.y))
                        diamond.addLine(to: CGPoint(x: c.x, y: c.y + 7.5))
                        diamond.addLine(to: CGPoint(x: c.x - 7.5, y: c.y))
                        diamond.closeSubpath()
                        context.fill(diamond, with: .color(spot.open ? .tujiInk : .tujiInk3))
                        context.stroke(diamond, with: .color(.tujiPaper), lineWidth: 2)
                    }
                }
                .accessibilityHidden(true)

                ForEach(Array(self.city.shapes.enumerated()), id: \.offset) { _, shape in
                    Text(verbatim: shape.name)
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(Self.isWater(shape) ? Color.tujiMapSeaInk : .tujiInk2)
                        .fixedSize()
                        .position(Self.place(shape.nameAt, size))
                        .accessibilityHidden(true)
                }

                ForEach(Array(self.city.spots.enumerated()), id: \.element.id) { index, spot in
                    if let tag = spot.tag {
                        self.tag(spot, number: index + 1)
                            .position(Self.place(tag, size))
                    }
                }
            }
        }
        .aspectRatio(self.city.aspect, contentMode: .fit)
        .background {
            ZStack {
                Color.tujiPaper
                self.tone.opacity(0.3)
            }
        }
        .clipped()
        // The tags were placed for these sizes; larger text would run them into each other.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private static func place(_ p: TravelPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    @ViewBuilder
    private func tag(_ spot: TravelSpot, number: Int) -> some View {
        let short = spot.tagShort == true
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let face = HStack(spacing: 6) {
            Text(verbatim: String(number))
                .font(.tujiLabel)
                .foregroundStyle(spot.open ? .tujiPaper : .tujiInk3)
                .frame(width: 20, height: 20)
                .background(
                    spot.open ? Color.tujiInk : .tujiPaper3,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay(alignment: .topTrailing) {
                    if self.photographed.contains(spot.id) {
                        Image(systemName: "camera.fill")
                            .font(.tujiIcon(7, weight: .bold))
                            .foregroundStyle(.tujiInk)
                            .frame(width: 14, height: 14)
                            .background(Color.tujiBrandPrimary, in: .circle)
                            .overlay { Circle().strokeBorder(.tujiInk, lineWidth: 1) }
                            .offset(x: 6, y: -7)
                    }
                }
            if !short {
                Text(verbatim: spot.name)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(spot.open ? .tujiInk : .tujiInk3)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 2)
        .padding(.trailing, short ? 2 : 10)
        .frame(height: 28)
        .background(.tujiPaper, in: shape)
        .overlay { shape.strokeBorder(spot.open ? Color.tujiInk : .tujiInk3, lineWidth: Border.bw2) }
        // A 44pt target round the 28pt tag.
        .padding(.vertical, 8)
        .contentShape(.rect)

        if spot.open, spotLocked(spot) {
            Button { self.presentPaywall() } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: spot.name))
        } else if spot.open {
            NavigationLink(value: TravelRoute.spot(id: spot.id)) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    self.photographed.contains(spot.id)
                        ? Text("\(spot.name)，你在這裡拍過")
                        : Text(verbatim: spot.name)
                )
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(spot.name)，還沒開"))
        }
    }

    private static func isWater(_ shape: TravelMapShape) -> Bool {
        switch shape {
        case .ring: false
        case .river, .water: true
        }
    }

    private static func draw(_ shape: TravelMapShape, in context: inout GraphicsContext, size: CGSize) {
        switch shape {
        case let .water(points, _, _):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: self.place(first, size))
            for point in points.dropFirst() {
                path.addLine(to: self.place(point, size))
            }
            path.closeSubpath()
            context.fill(path, with: .color(.tujiMapSea))
        case let .river(points, _, _):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: self.place(first, size))
            var previous = self.place(first, size)
            for point in points.dropFirst() {
                let next = self.place(point, size)
                let mid = CGPoint(x: (previous.x + next.x) / 2, y: (previous.y + next.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
                previous = next
            }
            path.addLine(to: previous)
            context.stroke(
                path,
                with: .color(.tujiMapRiver),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )
        case let .ring(center, radius, _, _):
            let c = self.place(center, size)
            let rect = CGRect(
                x: c.x - radius.x * size.width,
                y: c.y - radius.y * size.height,
                width: radius.x * size.width * 2,
                height: radius.y * size.height * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.tujiInk3),
                style: StrokeStyle(lineWidth: Border.bw2, dash: [8, 5])
            )
        }
    }
}

/// One spot under the city map: its number and name on the region's colour,
/// the picture of its first word, how it is written and read in Japanese, and
/// how far through its words this account is.
struct TravelSpotCard: View {
    let spot: TravelSpot
    let number: Int
    let tone: Color
    /// The spot's first word, when the dictionary has it.
    let cover: CardWord?
    let access: TravelSpotAccess
    /// Only a gated account is told a spot is free.
    let gated: Bool
    let studied: Int
    let photographed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(verbatim: String(self.number))
                    .font(.tujiLabel)
                    .foregroundStyle(self.spot.open ? .tujiPaper : .tujiInk3)
                    .frame(width: 20, height: 20)
                    .background(
                        self.spot.open ? Color.tujiInk : .tujiPaper2,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                Text(verbatim: self.spot.name)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(self.spot.open ? .tujiInk : .tujiInk2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if self.spot.open, self.access == .needsMembership {
                    Image(systemName: "lock.fill")
                        .font(.tujiIcon(11, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .accessibilityLabel(Text("學習這個景點需要永久會員"))
                } else if self.photographed {
                    Image(systemName: "camera.fill")
                        .font(.tujiIcon(11, weight: .semibold))
                        .foregroundStyle(.tujiInk)
                        .accessibilityLabel(Text("你在這裡拍過"))
                }
            }
            .padding(.horizontal, Space.s2)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.spot.open ? self.tone : .tujiPaper3)
            .overlay(alignment: .bottom) { Rectangle().fill(.tujiInk).frame(height: Border.bw2) }

            Color.tujiPaper2
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if self.spot.open, let cover = self.cover {
                        WordPicture(url: cover.imageURL, kind: cover.imageKind)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if self.spot.open, let cover = self.cover {
                        Text(verbatim: cover.word)
                            .font(.tujiLabel)
                            .foregroundStyle(.tujiInk)
                            .padding(.horizontal, Space.s2)
                            .frame(height: 22)
                            .background(.tujiPaper, in: Capsule())
                            .padding(Space.s2)
                    }
                }
                .clipped()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: self.spot.native)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(self.spot.open ? .tujiInk : .tujiInk3)
                    .lineLimit(1)
                Text(verbatim: self.spot.reading)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .lineLimit(1)
                self.status
                    .padding(.top, 2)
            }
            .padding(.horizontal, Space.s2)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.tujiPaper, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(self.spot.open ? Color.tujiInk : .tujiInk3, lineWidth: Border.bw2) }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if !self.spot.open {
            Text("還沒開")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        } else {
            HStack(spacing: Space.s2) {
                if self.studied > 0 {
                    Text("學過 \(self.studied) / \(self.spot.wordIds.count)")
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiAccumulationDeep)
                } else {
                    Text("\(self.spot.wordIds.count) 個詞")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
                if self.gated, self.access == .open {
                    Text("免費")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk2)
                        .padding(.horizontal, Space.s2)
                        .frame(height: 22)
                        .background(.tujiPaper2)
                }
            }
        }
    }
}

// The country from its real outline: one colour per region with somewhere to
// go, grey where nothing is open, and a card on the sea naming each region's
// open cities, joined to it by a dashed line.
//
// Everything is placed by the server in 0–1 of the map (tuji-web
// lib/travel/japan/map.ts), and the cards' lines come already broken, so this
// view only scales the picture. The type is fixed in size: the cards were laid
// out for these sizes and must not grow into each other.

import SwiftUI

struct TravelCountryMap: View {
    let destination: TravelDestination
    let outline: TravelCountryOutline
    /// A card was tapped; the screen scrolls to that region's cities.
    var onSelectRegion: (String) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: geo.size.width / self.outline.aspect)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    self.draw(in: &context, size: size)
                }
                .accessibilityHidden(true)

                ForEach(Array(self.outline.seas.enumerated()), id: \.offset) { _, sea in
                    Text(verbatim: sea.name)
                        .font(.tujiLabel)
                        .tracking(2)
                        .foregroundStyle(Color.tujiMapSeaInk)
                        .fixedSize()
                        .position(self.place(sea.at, in: size))
                        .accessibilityHidden(true)
                }

                ForEach(self.destination.regions) { region in
                    if region.card == nil, let at = region.labelAt {
                        let open = !self.destination.openCities(in: region).isEmpty
                        Text(verbatim: region.name)
                            .font(open ? .tujiBodySm(.strong) : .tujiLabel)
                            .foregroundStyle(open ? .tujiInk : .tujiInk2)
                            .fixedSize()
                            .position(self.place(at, in: size))
                            .accessibilityHidden(true)
                    }
                }

                // Moira stands in the open sea of the lower right, under the cards.
                Image("story-moira-check_map")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width * 0.25, height: size.width * 0.25)
                    .offset(x: size.width * 0.75, y: size.height - size.width * 0.25 - 8)
                    .accessibilityHidden(true)

                ForEach(self.destination.regions) { region in
                    if let card = region.card {
                        self.card(region, card, in: size)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .aspectRatio(self.outline.aspect, contentMode: .fit)
        .background(Color.tujiMapSea)
        .clipped()
        // The cards were laid out for these sizes; larger text would run them into each other.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(self.destination.name)地圖"))
    }

    private func place(_ p: TravelPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func cardRect(_ card: TravelRegionCard, in size: CGSize) -> CGRect {
        CGRect(
            x: card.at.x * size.width,
            y: card.at.y * size.height,
            width: card.width * size.width,
            height: TravelDecisions.cardHeight(lines: card.lines.count)
        )
    }

    private func card(_ region: TravelRegion, _ card: TravelRegionCard, in size: CGSize) -> some View {
        let rect = self.cardRect(card, in: size)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { self.onSelectRegion(region.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.tujiMapTone(region.tone))
                        .overlay { Circle().strokeBorder(.tujiInk, lineWidth: 1.5) }
                        .frame(width: 10, height: 10)
                    Text(verbatim: region.name)
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                }
                .frame(height: 20)
                ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                        .lineLimit(1)
                        .frame(height: 18)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .background(.tujiPaper, in: shape)
            .overlay { shape.strokeBorder(.tujiInk, lineWidth: Border.bw2) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityLabel(Text(verbatim: "\(region.name)：\(card.lines.joined(separator: " "))"))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        func path(_ points: [TravelPoint]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: self.place(first, in: size))
            for p in points.dropFirst() {
                path.addLine(to: self.place(p, in: size))
            }
            path.closeSubpath()
            return path
        }

        for frame in self.outline.frames {
            let rect = CGRect(
                x: frame.at.x * size.width,
                y: frame.at.y * size.height,
                width: frame.size.x * size.width,
                height: frame.size.y * size.height
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 12),
                with: .color(.tujiInk2),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        }

        // Each region filled, its edges drawn in paper so neighbours part;
        // then the coast in ink over everything.
        for region in self.destination.regions {
            let open = !self.destination.openCities(in: region).isEmpty
            let fill = open ? Color.tujiMapTone(region.tone) : .tujiPaper3
            for shape in region.shapes ?? [] {
                let p = path(shape)
                context.fill(p, with: .color(fill))
                context.stroke(p, with: .color(.tujiPaper), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
        }
        for island in self.outline.coast {
            context.stroke(
                path(island),
                with: .color(.tujiInk),
                style: StrokeStyle(lineWidth: Border.bw2, lineJoin: .round)
            )
        }

        for region in self.destination.regions {
            guard let card = region.card else { continue }
            let rect = self.cardRect(card, in: size)
            let end = self.place(card.pointAt, in: size)
            var line = Path()
            line.move(to: end)
            line.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
            context.stroke(
                line,
                with: .color(.tujiInk2),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
            )
            context.fill(
                Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)),
                with: .color(.tujiInk)
            )
        }

        for city in self.destination.cities {
            guard let at = city.mapAt else { continue }
            let c = self.place(at, in: size)
            let dot = Path(ellipseIn: CGRect(x: c.x - 3.2, y: c.y - 3.2, width: 6.4, height: 6.4))
            context.fill(dot, with: .color(.tujiInk))
            context.stroke(dot, with: .color(.tujiPaper), lineWidth: 1.4)
        }
    }
}

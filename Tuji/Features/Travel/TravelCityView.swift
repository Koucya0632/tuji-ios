// One city: a schematic map with its 景點 on it, and the same spots as a list.
//
// The map is three or four shapes the server describes — a loop line, a river,
// a bay — drawn here, with every name a `Text` so it follows the interface
// language. It is not for finding the way: it says roughly where each spot is
// relative to things a visitor already recognises.

import SwiftUI

struct TravelCityView: View {
    let cityId: String
    let destinationId: String

    @Environment(SettingsStore.self) private var settings
    @Environment(MasteryStore.self) private var mastery
    var store: TravelStore = .shared

    private var studyable: [String]? {
        LiveEffectiveEntitlement.shared.membership?.studyableCategories
    }

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {}
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.content
                }
                .padding(.bottom, Space.s6)
            }
        }
        .background(.tujiPaper)
        .navigationTitle(Text(verbatim: self.store.city(self.cityId, in: self.destinationId)?.name ?? ""))
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await self.store.loadIfNeeded(settings: self.settings)
            await self.mastery.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let city = self.store.city(self.cityId, in: self.destinationId) {
            TujiScreenTitle(localized: city.name)
            TravelCityMap(city: city)
                .padding(.bottom, Space.s3)
            TujiSection {
                ForEach(Array(city.spots.enumerated()), id: \.element.id) { index, spot in
                    self.row(spot, number: index + 1)
                }
            }
        } else if self.store.phase == .failed {
            TujiBlankState(kind: .failed, retry: { await self.store.reload(settings: self.settings) })
        } else if self.store.phase == .loaded {
            TujiBlankState(kind: .empty("這裡還沒開"))
        } else {
            TujiPageLoading()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s6)
        }
    }

    @ViewBuilder
    private func row(_ spot: TravelSpot, number: Int) -> some View {
        let row = TujiRow(
            leading: {
                HStack(spacing: Space.s3) {
                    TravelSpotMarker(number: number, open: spot.open)
                    Text(verbatim: spot.name)
                        .font(.tujiBody(.strong))
                        .foregroundStyle(spot.open ? .tujiInk : .tujiInk3)
                }
            },
            trailing: { self.trailing(spot) }
        )
        if spot.open {
            NavigationLink(value: TravelRoute.spot(id: spot.id)) { row }
                .tujiRowStyle()
        } else {
            row
        }
    }

    @ViewBuilder
    private func trailing(_ spot: TravelSpot) -> some View {
        if !spot.open {
            Text("還沒開")
                .font(.tujiBodySm)
                .foregroundStyle(.tujiInk3)
        } else {
            let studied = TravelDecisions.studiedCount(of: spot, scores: self.mastery.byId)
            HStack(spacing: Space.s2) {
                if TravelDecisions.access(to: spot, studyable: self.studyable) == .needsMembership {
                    Image(systemName: "lock.fill")
                        .font(.tujiIcon(11, weight: .semibold))
                        .foregroundStyle(.tujiInk3)
                        .accessibilityLabel(Text("學習這個景點需要永久會員"))
                } else if self.studyable != nil {
                    // Only a gated account is told a spot is free — to a
                    // member every spot is, and the word would be noise.
                    Text("免費")
                        .font(.tujiLabel)
                        .foregroundStyle(.tujiInk2)
                        .padding(.horizontal, Space.s2)
                        .frame(height: 24)
                        .background(.tujiPaper2)
                }
                if studied > 0 {
                    Text("學過 \(studied) / \(spot.wordIds.count)")
                        .font(.tujiBodySm(.strong))
                        .foregroundStyle(.tujiAccumulationDeep)
                } else {
                    Text("\(spot.wordIds.count) 樣東西")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk2)
                }
                Image(systemName: "chevron.right")
                    .font(.tujiIcon(13, weight: .semibold))
                    .foregroundStyle(.tujiInk3)
            }
        }
    }
}

/// The numbered square that stands for a spot, on the map and in the list.
struct TravelSpotMarker: View {
    let number: Int
    let open: Bool

    var body: some View {
        Text(verbatim: String(self.number))
            .font(.tujiBodySm(.strong))
            .foregroundStyle(self.open ? .tujiPaper : .tujiInk3)
            .frame(width: 28, height: 28)
            .background(self.open ? Color.tujiInk : .tujiPaper3)
            .accessibilityHidden(true)
    }
}

struct TravelCityMap: View {
    let city: TravelCity

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for shape in self.city.shapes {
                        Self.draw(shape, in: &context, size: size)
                    }
                }
                .accessibilityHidden(true)

                ForEach(Array(self.city.shapes.enumerated()), id: \.offset) { _, shape in
                    Text(verbatim: shape.name)
                        .font(.tujiLabel)
                        .tracking(0.5)
                        .foregroundStyle(Self.isWater(shape) ? .tujiAccumulationDeep : .tujiInk2)
                        .fixedSize()
                        .position(x: shape.nameAt.x * size.width, y: shape.nameAt.y * size.height)
                        .accessibilityHidden(true)
                }

                ForEach(Array(self.city.spots.enumerated()), id: \.element.id) { index, spot in
                    self.pin(spot, number: index + 1)
                        .position(x: spot.at.x * size.width, y: spot.at.y * size.height)
                }
            }
        }
        .aspectRatio(self.city.aspect, contentMode: .fit)
        .background(.tujiPaper2)
        .clipped()
    }

    @ViewBuilder
    private func pin(_ spot: TravelSpot, number: Int) -> some View {
        let marker = TravelSpotMarker(number: number, open: spot.open)
            // The name hangs off one side of the square, so the square itself
            // stays on the spot's position whichever side that is.
            .overlay(alignment: spot.label == .right ? .leading : .trailing) {
                Text(verbatim: spot.name)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(spot.open ? .tujiInk : .tujiInk3)
                    .fixedSize()
                    .offset(x: spot.label == .right ? 34 : -34)
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        if spot.open {
            NavigationLink(value: TravelRoute.spot(id: spot.id)) { marker }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: spot.name))
        } else {
            marker
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
        func place(_ p: TravelPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: p.y * size.height)
        }
        switch shape {
        case let .water(points, _, _):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: place(first))
            for point in points.dropFirst() {
                path.addLine(to: place(point))
            }
            path.closeSubpath()
            context.fill(path, with: .color(.tujiAccumulationSoft))
        case let .river(points, _, _):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: place(first))
            // A smooth line through the points: each one is the end of a curve
            // whose control point is the midpoint before it.
            var previous = place(first)
            for point in points.dropFirst() {
                let next = place(point)
                let mid = CGPoint(x: (previous.x + next.x) / 2, y: (previous.y + next.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
                previous = next
            }
            path.addLine(to: previous)
            context.stroke(
                path,
                with: .color(.tujiAccumulationSoft),
                style: StrokeStyle(lineWidth: size.width * 0.036, lineCap: .round, lineJoin: .round)
            )
        case let .ring(center, radius, _, _):
            let c = place(center)
            let rect = CGRect(
                x: c.x - radius.x * size.width,
                y: c.y - radius.y * size.height,
                width: radius.x * size.width * 2,
                height: radius.y * size.height * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(.tujiInk),
                style: StrokeStyle(lineWidth: Border.bw2, dash: [10, 4])
            )
        }
    }
}

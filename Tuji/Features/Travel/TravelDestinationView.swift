// One destination: the country's map, and its open cities listed underneath,
// grouped by region.
//
// The map is the real outline when the server sends one (TravelCountryMap):
// a colour per region with somewhere to go and a card naming its cities, which
// scrolls the list to them. An older server sends only cells, drawn as the
// grid below. Regions with nothing open share a single 還沒開 row.

import SwiftUI

struct TravelDestinationView: View {
    let destinationId: String

    @Environment(SettingsStore.self) private var settings
    var store: TravelStore = .shared

    var body: some View {
        VStack(spacing: 0) {
            TujiNavBar(leading: .back) {}
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        self.content(scrollTo: { id in
                            withAnimation(Motion.ease(Motion.d2)) { reader.scrollTo(id, anchor: .top) }
                        })
                    }
                    .padding(.bottom, Space.s6)
                }
            }
        }
        .background(.tujiPaper)
        .navigationTitle(Text(verbatim: self.store.destination(self.destinationId)?.name ?? ""))
        .toolbar(.hidden, for: .navigationBar)
        .task { await self.store.loadIfNeeded(settings: self.settings) }
    }

    @ViewBuilder
    private func content(scrollTo: @escaping (String) -> Void) -> some View {
        if let destination = self.store.destination(self.destinationId) {
            TujiScreenTitle(localized: destination.name)
            if let outline = destination.outline {
                Text("\(destination.cities.count) 個城市 · \(TravelDecisions.openSpotCount(destination)) 個景點")
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk2)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, -Space.s3)
                    .padding(.bottom, Space.s3)
                TravelCountryMap(destination: destination, outline: outline, onSelectRegion: scrollTo)
                self.regionSections(destination)
            } else {
                TravelGridMap(destination: destination)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s4)
                self.cityRows(destination)
            }
        } else if self.store.phase == .failed {
            TujiBlankState(kind: .failed, retry: { await self.store.reload(settings: self.settings) })
        } else if self.store.phase == .loaded {
            // The destination closed while this screen was on the stack.
            TujiBlankState(kind: .empty("這裡還沒開"))
        } else {
            TujiPageLoading()
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s6)
        }
    }

    @ViewBuilder
    private func cityRows(_ destination: TravelDestination) -> some View {
        let open = destination.regions.flatMap { region in
            destination.openCities(in: region).map { (region: region, city: $0) }
        }
        let hasClosedRegion = destination.regions.contains { destination.openCities(in: $0).isEmpty }
        TujiSection {
            ForEach(open, id: \.city.id) { entry in
                NavigationLink(value: TravelRoute.city(id: entry.city.id, destination: destination.id)) {
                    TujiRow(
                        leading: {
                            HStack(spacing: Space.s3) {
                                Rectangle()
                                    .fill(.tujiBrandPrimary)
                                    .overlay { Rectangle().strokeBorder(.tujiInk, lineWidth: Border.bw2) }
                                    .frame(width: 44, height: 44)
                                TujiRowLabel(
                                    localized: entry.city.name,
                                    localizedSubtitle: tujiLocalized(
                                        "\(entry.region.name) · \(entry.city.openSpots.count) 個景點"
                                    )
                                )
                            }
                        },
                        trailing: { TujiRowAccessory(value: nil, showsArrow: true) }
                    )
                }
                .tujiRowStyle()
            }
            if hasClosedRegion {
                TujiRow(
                    leading: {
                        HStack(spacing: Space.s3) {
                            Rectangle()
                                .fill(.tujiPaper3)
                                .frame(width: 44, height: 44)
                            TujiRowLabel(label: "其他地區", subtitle: "還沒開")
                        }
                    },
                    trailing: { EmptyView() }
                )
            }
        }
    }

    /// Each region with an open city: its name and colour, then its cities.
    /// The section's id is the region's, for the map's cards to scroll to.
    @ViewBuilder
    private func regionSections(_ destination: TravelDestination) -> some View {
        ForEach(destination.regions.filter { !destination.openCities(in: $0).isEmpty }) { region in
            let cities = destination.openCities(in: region)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(Color.tujiMapTone(region.tone))
                        .overlay { Circle().strokeBorder(.tujiInk, lineWidth: 1.5) }
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(verbatim: region.name)
                        .font(.tujiH3)
                        .foregroundStyle(.tujiInk)
                    Text("\(cities.count) 個城市")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiInk3)
                }
                .padding(.horizontal, Space.s4)
                // The heading sits right on its rows: the section's own 40pt is turned off below.
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                TujiSection(topSpacing: 0) {
                    ForEach(cities) { city in
                        NavigationLink(value: TravelRoute.city(id: city.id, destination: destination.id)) {
                            TujiRow(
                                leading: {
                                    HStack(spacing: Space.s3) {
                                        TravelStamp(
                                            mark: TravelDecisions.stampMark(city.name),
                                            fill: .tujiMapTone(region.tone)
                                        )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: city.name)
                                                .font(.tujiH3)
                                                .foregroundStyle(.tujiInk)
                                            Text(verbatim: TravelDecisions.spotPreview(city))
                                                .font(.tujiBodySm)
                                                .foregroundStyle(.tujiInk3)
                                                .lineLimit(1)
                                        }
                                        .padding(.vertical, Space.s2)
                                    }
                                },
                                trailing: {
                                    TujiRowAccessory(
                                        value: tujiLocalized("\(city.openSpots.count) 個景點"),
                                        showsArrow: true
                                    )
                                }
                            )
                        }
                        .tujiRowStyle()
                    }
                }
            }
            .id(region.id)
        }
        let closed = TravelDecisions.closedRegions(destination)
        if !closed.isEmpty {
            TujiSection {
                TujiRow(
                    leading: {
                        HStack(spacing: Space.s3) {
                            Circle()
                                .strokeBorder(.tujiInk3, style: StrokeStyle(lineWidth: Border.bw2, dash: [4, 3]))
                                .background(Circle().fill(.tujiPaper3))
                                .frame(width: 44, height: 44)
                                .accessibilityHidden(true)
                            TujiRowLabel(
                                localized: closed.map(\.name).joined(separator: "・"),
                                localizedSubtitle: tujiLocalized("還沒開")
                            )
                        }
                    },
                    trailing: { EmptyView() }
                )
            }
        }
    }
}

/// A city's stamp: its first character inside a dashed ring, on its region's colour.
struct TravelStamp: View {
    let mark: String
    let fill: Color

    var body: some View {
        Circle()
            .fill(self.fill)
            .overlay { Circle().strokeBorder(.tujiInk, lineWidth: Border.bw2) }
            .overlay {
                Circle()
                    .strokeBorder(.tujiInk, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                    .padding(6)
            }
            .overlay {
                Text(verbatim: self.mark)
                    .font(.tujiBodySm(.strong))
                    .foregroundStyle(.tujiInk)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }
}

/// The country, one square per cell.
struct TravelGridMap: View {
    let destination: TravelDestination

    private let gap: CGFloat = 2
    /// Wider than this and the cells stop reading as a map of anything.
    private let maxWidth: CGFloat = 360

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, self.maxWidth)
            let side = TravelDecisions.cellSide(width: width, columns: self.destination.grid.columns, gap: self.gap)
            ZStack(alignment: .topLeading) {
                ForEach(self.destination.regions) { region in
                    let lit = !self.destination.openCities(in: region).isEmpty
                    ForEach(region.tiles, id: \.self) { tile in
                        let origin = TravelDecisions.cellOrigin(tile, side: side, gap: self.gap)
                        Rectangle()
                            .fill(lit ? Color.tujiBrandPrimary : .tujiPaper3)
                            .overlay {
                                if lit { Rectangle().strokeBorder(.tujiInk, lineWidth: Border.bw2) }
                            }
                            .frame(width: side, height: side)
                            .offset(x: origin.x, y: origin.y)
                    }
                    let at = TravelDecisions.cellOrigin(region.nameAt, side: side, gap: self.gap)
                    Text(verbatim: region.name)
                        .font(lit ? .tujiBodySm(.strong) : .tujiLabel)
                        .foregroundStyle(lit ? .tujiInk : .tujiInk2)
                        .fixedSize()
                        .position(x: at.x, y: at.y)
                }
            }
            .frame(width: width, height: self.height(side: side), alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                // The lower right of the grid is open sea on every map drawn
                // so far, which is where Moira stands.
                Image("story-moira-point")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side * 4.5, height: side * 4.5)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(self.aspect, contentMode: .fit)
        .frame(maxWidth: self.maxWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(self.destination.name)地圖"))
    }

    private var aspect: CGFloat {
        CGFloat(self.destination.grid.columns) / CGFloat(max(1, self.destination.grid.rows))
    }

    private func height(side: CGFloat) -> CGFloat {
        let rows = CGFloat(self.destination.grid.rows)
        return side * rows + self.gap * max(0, rows - 1)
    }
}

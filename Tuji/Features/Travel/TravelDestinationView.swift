// One destination: the country as a grid of cells, lit where there is a city
// to open, and those cities listed underneath.
//
// The map is drawn from the cells the server sends. Nothing is tappable but
// what is lit; a region with no city yet is the paper's third step and a
// single 還沒開 row speaks for all of them.

import SwiftUI

struct TravelDestinationView: View {
    let destinationId: String

    @Environment(SettingsStore.self) private var settings
    var store: TravelStore = .shared

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
        .navigationTitle(Text(verbatim: self.store.destination(self.destinationId)?.name ?? ""))
        .toolbar(.hidden, for: .navigationBar)
        .task { await self.store.loadIfNeeded(settings: self.settings) }
    }

    @ViewBuilder
    private var content: some View {
        if let destination = self.store.destination(self.destinationId) {
            TujiScreenTitle(localized: destination.name)
            TravelGridMap(destination: destination)
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            self.cityRows(destination)
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

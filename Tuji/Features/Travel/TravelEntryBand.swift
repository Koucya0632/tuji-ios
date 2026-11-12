// The way into 跟著 Moira 去旅遊, at the top of 物見's 探索 shelf.
//
// Moira sits on 瞳黃 rather than on the ink: she is a black cat, and on the ink
// block only her eyes would show.

import SwiftUI

struct TravelEntryBand: View {
    let destination: TravelDestination

    var body: some View {
        NavigationLink(value: TravelRoute.destination(id: self.destination.id)) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("跟著 Moira 去旅遊")
                        .font(.tujiH3)
                        .foregroundStyle(.tujiPaper)
                    Text("\(self.destination.name) · \(TravelDecisions.openSpotCount(self.destination)) 個景點")
                        .font(.tujiBodySm)
                        .foregroundStyle(.tujiPaper3)
                    Spacer(minLength: Space.s2)
                    HStack(spacing: Space.s1) {
                        Text("看地圖")
                            .font(.tujiBodySm(.strong))
                        Image(systemName: "chevron.right")
                            .font(.tujiIcon(12, weight: .bold))
                    }
                    .foregroundStyle(.tujiBrandPrimary)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(.tujiInk)

                Image("story-moira-check_map")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(Space.s1)
                    .frame(width: 112)
                    .frame(maxHeight: .infinity)
                    .background(.tujiBrandPrimary)
                    .accessibilityHidden(true)
            }
            .frame(height: 112)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

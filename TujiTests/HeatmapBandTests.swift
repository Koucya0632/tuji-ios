// Pins the 累積 heatmap's four steps.
//
// The bands and their colours used to be two `private func`s on `HeatmapGrid`,
// and one of them was wrong: `tintForLevel` returned `.tujiAccumulation` for
// both the 5–12 band and its `default`, so 13+ was indistinguishable from 5–12
// on the grid, and the legend — which walks the levels rather than listing
// colours — drew that swatch twice out of four. Nothing could see it, because
// the only way in was through a `View`'s body.

import SwiftUI
import Testing
@testable import Tuji

struct HeatmapBandTests {
    @Test
    func countsFallIntoTheirBand() {
        #expect(HeatmapBand(count: 0) == .none)
        #expect(HeatmapBand(count: 1) == .light)
        #expect(HeatmapBand(count: 4) == .light)
        #expect(HeatmapBand(count: 5) == .medium)
        #expect(HeatmapBand(count: 12) == .medium)
        #expect(HeatmapBand(count: 13) == .heavy)
        #expect(HeatmapBand(count: 999) == .heavy)
    }

    /// A day cannot be answered a negative number of times, but the count comes
    /// off the wire — a band that traps is worse than one that reads empty.
    @Test
    func aNegativeCountReadsAsEmptyRatherThanTrapping() {
        #expect(HeatmapBand(count: -1) == .none)
    }

    /// The defect, stated directly: four bands, four *distinct* colours. The
    /// legend draws one swatch per band, so any two bands sharing a colour make
    /// it print a duplicate and make two densities indistinguishable on the grid.
    @Test
    func everyBandHasItsOwnColour() {
        let tints = HeatmapBand.allCases.map(\.tint)
        #expect(tints.count == 4)
        #expect(Set(tints.map(\.description)).count == 4)
    }

    /// `allCases` is what the legend iterates, so its order is the ramp the
    /// reader sees under 少 → 多.
    @Test
    func bandsAreOrderedFromEmptyToHeavy() {
        #expect(HeatmapBand.allCases == [.none, .light, .medium, .heavy])
    }
}

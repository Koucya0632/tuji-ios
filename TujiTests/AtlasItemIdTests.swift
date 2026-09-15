import Testing
@testable import Tuji

/// `atlas:<itemId>` — the one routing decision five call sites used to spell
/// out as `hasPrefix("atlas:")`.
struct AtlasItemIdTests {
    @Test
    func aCapturedWordIdYieldsItsItemId() {
        #expect("atlas:9b2c".atlasItemId == "9b2c")
    }

    @Test
    func catalogueAndSavedIdsAreNotAtlasItems() {
        #expect("kettle".atlasItemId == nil)
        #expect("saved:kettle-by-tj".atlasItemId == nil)
    }

    /// A bare prefix names no item; routing it to the atlas detail would ask
    /// for an empty id.
    @Test
    func aBarePrefixIsNotAnItem() {
        #expect("atlas:".atlasItemId == nil)
    }
}

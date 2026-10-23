import Foundation
import Testing
@testable import Tuji

/// What choosing a 主題組合 does, and when one reads as chosen — see
/// `TopicPresetChoice` and CONTEXT.md.
struct TopicPresetChoiceTests {
    private let catalog: Set<String> = ["campus", "bank", "restaurant", "onsen-ryokan", "kitchen", "custom", "community"]
    private let student = TopicPreset(id: "student", name: "留學生", categoryIds: ["campus", "bank"], isDefault: true)
    private let travel = TopicPreset(id: "travel", name: "旅遊", categoryIds: ["restaurant", "onsen-ryokan"], isDefault: false)

    /// Replaces the public themes; the sources are not topics and stay put.
    @Test
    func choosingReplacesThePublicThemesAndKeepsTheSources() {
        let next = TopicPresetChoice.applying(self.student, to: ["kitchen", "custom"], catalogIds: self.catalog)
        #expect(next == ["campus", "bank", "custom"])
    }

    /// A source the user had turned off is not turned back on.
    @Test
    func choosingDoesNotTickASourceThatWasOff() {
        let next = TopicPresetChoice.applying(self.student, to: [], catalogIds: self.catalog)
        #expect(next == ["campus", "bank"])
    }

    @Test
    func aSecondPresetReplacesTheFirstRatherThanStacking() {
        let first = TopicPresetChoice.applying(self.student, to: ["community"], catalogIds: self.catalog)
        let second = TopicPresetChoice.applying(self.travel, to: first, catalogIds: self.catalog)
        #expect(second == ["restaurant", "onsen-ryokan", "community"])
    }

    @Test
    func aThemeMissingFromTheCatalogIsNeverTicked() {
        let preset = TopicPreset(id: "student", name: "留學生", categoryIds: ["campus", "retired-theme"], isDefault: true)
        #expect(TopicPresetChoice.applying(preset, to: [], catalogIds: self.catalog) == ["campus"])
    }

    @Test
    func chosenOnlyWhileThePublicThemesMatchExactly() {
        #expect(TopicPresetChoice.isChosen(self.student, selection: ["campus", "bank", "custom"], catalogIds: self.catalog))
        #expect(!TopicPresetChoice.isChosen(self.student, selection: ["campus", "bank", "kitchen"], catalogIds: self.catalog))
        #expect(!TopicPresetChoice.isChosen(self.student, selection: ["campus"], catalogIds: self.catalog))
    }

    @Test
    func aPresetWithNoThemesLeftIsNeverChosen() {
        let gone = TopicPreset(id: "x", name: "x", categoryIds: ["retired-theme"], isDefault: false)
        #expect(!TopicPresetChoice.isChosen(gone, selection: ["custom"], catalogIds: self.catalog))
    }

    /// Whole or not at all: one locked theme locks the preset.
    @Test
    func anyLockedThemeLocksThePreset() {
        let free: Set<String> = ["campus", "bank"]
        #expect(!TopicPresetChoice.isLocked(self.student, catalogIds: self.catalog) { !free.contains($0) })
        let mixed = TopicPreset(id: "wh", name: "打工度假", categoryIds: ["bank", "restaurant"], isDefault: false)
        #expect(TopicPresetChoice.isLocked(mixed, catalogIds: self.catalog) { !free.contains($0) })
    }

    // MARK: - Wire

    /// A backend from before 主題組合 sends no `presets`; that is not a decode failure.
    @Test
    func aResponseWithoutPresetsDecodesToNone() throws {
        let json = Data(#"{"categories":[]}"#.utf8)
        #expect(try JSONDecoder().decode(CategoriesResponse.self, from: json).presets == [])
    }

    @Test
    func presetsDecodeFromTheCategoriesResponse() throws {
        let json = Data(#"{"categories":[],"presets":[{"id":"student","name":"留學生","categoryIds":["campus"],"isDefault":true}]}"#.utf8)
        let presets = try JSONDecoder().decode(CategoriesResponse.self, from: json).presets
        #expect(presets == [TopicPreset(id: "student", name: "留學生", categoryIds: ["campus"], isDefault: true)])
    }
}

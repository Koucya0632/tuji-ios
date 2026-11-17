import Foundation

/// What choosing a 主題組合 does to the 學習主題, and when one reads as chosen.
///
/// The account never records a preset (CONTEXT.md, 主題組合): choosing one is
/// re-ticking the themes by hand in one go, and "chosen" is read back off the
/// ticks. Both rules live here so the picker and Setup cannot each grow their
/// own version of "which ids are the public ones".
enum TopicPresetChoice {
    /// The sources — 自製圖鑑 and 物見收藏 — are not topics. A preset never
    /// touches them.
    static let sourceIDs = Set(StudyCategoryDefaults.atlasCategoryIDs)

    /// The preset's themes that exist in this catalog.
    static func themes(of preset: TopicPreset, catalogIds: Set<String>) -> Set<String> {
        Set(preset.categoryIds).intersection(catalogIds).subtracting(self.sourceIDs)
    }

    /// The selection after choosing `preset`: its public themes replace the
    /// visible public ones; hidden regions and sources stay as they were.
    static func applying(_ preset: TopicPreset, to selection: Set<String>, catalogIds: Set<String>) -> Set<String> {
        let visibleTopics = catalogIds.subtracting(self.sourceIDs)
        return self.replacingVisible(selection, visibleIds: visibleTopics, with: self.themes(of: preset, catalogIds: catalogIds))
    }

    static func replacingVisible(_ selection: Set<String>, visibleIds: Set<String>, with replacement: Set<String>) -> Set<String> {
        selection.subtracting(visibleIds).union(replacement.intersection(visibleIds))
    }

    static func hasOnlyHiddenSelection(_ selection: Set<String>, visibleIds: Set<String>) -> Bool {
        !selection.isEmpty && selection.isDisjoint(with: visibleIds)
    }

    /// Chosen only while the ticked public themes are exactly the preset's —
    /// one more or one fewer and it is not.
    static func isChosen(_ preset: TopicPreset, selection: Set<String>, catalogIds: Set<String>) -> Bool {
        let themes = self.themes(of: preset, catalogIds: catalogIds)
        return !themes.isEmpty && selection.intersection(catalogIds).subtracting(self.sourceIDs) == themes
    }

    /// Locked when any one of its themes is: a preset is chosen whole or not
    /// at all, never half-applied.
    static func isLocked(_ preset: TopicPreset, catalogIds: Set<String>, isThemeLocked: (String) -> Bool) -> Bool {
        self.themes(of: preset, catalogIds: catalogIds).contains(where: isThemeLocked)
    }
}

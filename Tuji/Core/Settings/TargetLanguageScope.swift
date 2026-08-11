// 當前圖鑑語言 — the target language the session is scoped to, as a screen sees it.
//
// Four 圖鑑 screens needed this and each invented its own way to get it: the
// manage screen pushed it into its model from `onAppear` + `onChange` (so the
// model was constructed holding `.ja` and was wrong until the first appear),
// 我的合集 and 公開圖鑑 recomputed a private `settings.current.learningDirection
// .targetLanguage` per render, and 物見 baked it into a String `.task(id:)` key.
// The derivation itself was spelled out ten times.
//
// It is an environment value rather than a read seam protocol because the
// consumers that matter most are deep in the view tree — `TujiHeadword` resolves
// an untagged word against it — and threading a store reference down to a
// component that draws one word is exactly the coupling the seam should prevent.
// `TujiApp` supplies the live value from `SettingsStore`; nothing else writes it.

import SwiftUI

extension EnvironmentValues {
    /// The target language of the user's current learning direction.
    ///
    /// The default matches `UserSettings.default.learningDirection` (`.zhEn`),
    /// so a preview or a detached view renders the same thing a brand-new
    /// account sees rather than an arbitrary language.
    @Entry var targetLanguage: TargetLanguage = .en
}

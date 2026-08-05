// Option data for the settings pickers.
//
// These used to be three pushed screens (`LangPickerView`, `AccentPickerView`,
// `DailyGoalPickerView`), each wrapping a native `List` around a handful of
// rows. C.8 turns single-select settings into a bottom sheet, so the screens
// went away and only the data they carried is left.

import SwiftUI

enum SettingsOptions {
    static let dailyGoals: [Int] = [5, 10, 15, 20, 30, 50]

    struct Accent: Identifiable {
        let code: String
        let label: LocalizedStringKey
        let detail: LocalizedStringKey

        var id: String {
            self.code
        }
    }

    static let accents: [Accent] = [
        Accent(code: "us", label: "美式", detail: "en-US · 預設"),
        Accent(code: "uk", label: "英式", detail: "en-GB")
    ]
}

// UILanguage raw values are the wire contract with tuji-web
// (lib/settings.ts UI_LANGS) — the first test pins the set so adding or
// renaming a language breaks CI instead of being silently clamped to
// zh-Hant by the server. The rest pin the fallback + device-detection
// rules that decide a first-run user's interface language.

import Foundation
import Testing
@testable import Tuji

struct UILanguageTests {
    @Test
    func rawValuesMatchBackendWhitelist() {
        #expect(UILanguage.allCases.map(\.rawValue) == ["zh-Hant", "zh-Hans", "ja", "en"])
    }

    @Test
    func codeInitResolvesKnownCodes() {
        #expect(UILanguage(code: "zh-Hant") == .zhHant)
        #expect(UILanguage(code: "zh-Hans") == .zhHans)
        #expect(UILanguage(code: "ja") == .ja)
        #expect(UILanguage(code: "en") == .en)
    }

    @Test
    func codeInitClampsUnknownCodesToZhHant() {
        #expect(UILanguage(code: "ko") == .zhHant)
        #expect(UILanguage(code: "") == .zhHant)
        #expect(UILanguage(code: nil) == .zhHant)
    }

    @Test
    func detectMatchesSupportedLanguages() {
        #expect(UILanguage.detect(from: ["ja-JP"]) == .ja)
        #expect(UILanguage.detect(from: ["en-GB"]) == .en)
        #expect(UILanguage.detect(from: ["zh-Hans-CN"]) == .zhHans)
        #expect(UILanguage.detect(from: ["zh-Hant-TW"]) == .zhHant)
    }

    @Test
    func detectInfersChineseScriptFromRegion() {
        #expect(UILanguage.detect(from: ["zh-CN"]) == .zhHans)
        #expect(UILanguage.detect(from: ["zh-SG"]) == .zhHans)
        #expect(UILanguage.detect(from: ["zh-TW"]) == .zhHant)
        #expect(UILanguage.detect(from: ["zh-HK"]) == .zhHant)
        #expect(UILanguage.detect(from: ["zh"]) == .zhHant)
    }

    @Test
    func detectSkipsUnsupportedTagsAndFallsBackToZhHant() {
        #expect(UILanguage.detect(from: ["fr-FR", "ja-JP"]) == .ja)
        #expect(UILanguage.detect(from: ["fr-FR"]) == .zhHant)
        #expect(UILanguage.detect(from: []) == .zhHant)
    }

    @Test
    func contentLanguageOnlyDivergesForSimplified() {
        #expect(UILanguage.zhHans.contentLanguageCode == "zh-Hans")
        #expect(UILanguage.zhHant.contentLanguageCode == "zh-Hant")
        #expect(UILanguage.ja.contentLanguageCode == "zh-Hant")
        #expect(UILanguage.en.contentLanguageCode == "zh-Hant")
    }

    @Test
    func localeMatchesWireCode() {
        #expect(UILanguage.zhHant.locale.identifier == "zh-Hant")
        #expect(UILanguage.ja.locale.identifier == "ja")
    }

    @Test
    func userSettingsAccessorRoundTrips() {
        var settings = UserSettings.default
        settings.uiLanguage = .ja
        #expect(settings.uiLang == "ja")
        settings.uiLang = "nonsense"
        #expect(settings.uiLanguage == .zhHant)
    }
}

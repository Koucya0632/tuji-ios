// The app's own localisation entry point — 145 call sites across 37 files.
//
// It lived in `SettingsStore.swift`, so `APIError`, `Atlas`, `AtlasCommunity`
// and `TargetLanguage` — none of which have anything to do with a settings
// store — all depended transitively on a file named after a `@MainActor`
// `@Observable` singleton. The function is `nonisolated` and reads
// `UserDefaults` directly *precisely so that it does not need that store*.
//
// The same lesson `CONTEXT.md` records twice — a module named after one of its
// callers does not get found by the next one (`ImageIntake ← AvatarPicker`,
// `TileBoard ← NewFlowCoordinator`) — except here it was not even a caller.
//
// Pure relocation: no interface change, no behaviour change.

import Foundation

/// UserDefaults key mirroring `SettingsStore.current.uiLang` for nonisolated reads.
nonisolated let tujiUILangDefaultsKey = "tuji.ui.lang"

private nonisolated let tujiLProjLock = NSLock()
private nonisolated(unsafe) var tujiLProjCache: [String: Bundle] = [:]

/// The compiled `.lproj` bundle for a uiLang code, cached. Falls back to the
/// main bundle (whose lookups yield the zh-Hant source strings) for unknown or
/// missing codes.
private nonisolated func tujiLProjBundle(_ code: String) -> Bundle {
    tujiLProjLock.lock()
    defer { tujiLProjLock.unlock() }
    if let cached = tujiLProjCache[code] { return cached }
    let bundle: Bundle =
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
        let lproj = Bundle(path: path) {
            lproj
        } else {
            .main
        }
    tujiLProjCache[code] = bundle
    return bundle
}

/// Localize a zh-Hant source string into the user's chosen in-app UI language.
///
/// The app overrides only the SwiftUI *environment* locale (see `TujiApp`), not
/// the process locale. Crucially, `String(localized:locale:)`'s `locale` param
/// only affects interpolation formatting — it does NOT choose which strings
/// table is loaded, which still follows the process language. So we resolve the
/// explicit `.lproj` bundle for the uiLang and look the key up there. Reads the
/// mirrored uiLang from UserDefaults (thread-safe, usable off the main actor).
nonisolated func tujiLocalized(_ key: String.LocalizationValue) -> String {
    let code = UserDefaults.standard.string(forKey: tujiUILangDefaultsKey)
        ?? UILanguage.deviceDefault.rawValue
    return tujiLocalized(key, lang: code)
}

/// As `tujiLocalized`, but for an explicitly supplied uiLang code (e.g. a draft
/// that carries its own language rather than the live app setting).
nonisolated func tujiLocalized(_ key: String.LocalizationValue, lang code: String) -> String {
    String(localized: key, bundle: tujiLProjBundle(code), locale: Locale(identifier: code))
}

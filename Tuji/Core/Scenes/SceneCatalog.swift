// The 場面 bundled with the app. Everything 「進店前看一眼」 needs ships inside
// the binary, so it opens and plays in airplane mode.
//
// The ids are listed rather than discovered: the list is the display order, and
// Xcode's synchronized folders copy resources flat into the bundle, where a
// scene file is one JSON among any others.

import Foundation
import OSLog

nonisolated struct SceneCatalog {
    let scenes: [PracticeScene]

    static let bundledIDs: [SceneID] = [
        SceneID(rawValue: "konbini-checkout"),
        SceneID(rawValue: "restaurant")
    ]

    /// What the screens read. A scene that fails to decode is left out and
    /// logged; `SceneContentTests` decodes them strictly so that never ships.
    static let bundled: SceneCatalog = {
        let log = Logger(subsystem: "app.tuji.ios", category: "scenes")
        let scenes = Self.bundledIDs.compactMap { id -> PracticeScene? in
            do {
                return try Self.decode(id, bundle: .main)
            } catch {
                log.error("scene \(id.rawValue, privacy: .public) failed to load: \(error, privacy: .public)")
                return nil
            }
        }
        return SceneCatalog(scenes: scenes)
    }()

    static func load(bundle: Bundle) throws -> SceneCatalog {
        try SceneCatalog(scenes: self.bundledIDs.map { try self.decode($0, bundle: bundle) })
    }

    func scene(_ id: SceneID) -> PracticeScene? {
        self.scenes.first { $0.id == id }
    }

    static func decode(_ id: SceneID, bundle: Bundle) throws -> PracticeScene {
        guard let url = self.resource(id.rawValue + ".json", subdirectories: ["Scenes"], bundle: bundle) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: id.rawValue + ".json"])
        }
        return try JSONDecoder().decode(PracticeScene.self, from: Data(contentsOf: url))
    }

    /// A bundled clip, or nil when the audio step has not produced it yet. The
    /// caller then reads the line with on-device synthesis.
    static func audioURL(_ file: String, bundle: Bundle = .main) -> URL? {
        self.resource(file, subdirectories: ["audio", "Scenes/audio"], bundle: bundle)
    }

    private static func resource(_ file: String, subdirectories: [String], bundle: Bundle) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        if let flat = bundle.url(forResource: name, withExtension: ext) { return flat }
        for directory in subdirectories {
            if let nested = bundle.url(forResource: name, withExtension: ext, subdirectory: directory) {
                return nested
            }
        }
        return nil
    }
}

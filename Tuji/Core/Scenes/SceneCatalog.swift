// The 場面 bundled with the app. Everything 「進店前看一眼」 needs ships inside
// the binary, so it opens and plays in airplane mode.
//
// The ids are listed in `Scenes/index.json` rather than discovered: the groups
// there are the display order, and Xcode's synchronized folders copy resources
// flat into the bundle, where a scene file is one JSON among any others. Adding
// a scene is a JSON file plus a line in the index, with no Swift.
//
// `released` names the scenes a Release build shows. The rest are drafts that
// still wait for native review, so only Debug builds list them.

import Foundation
import OSLog

nonisolated struct SceneGroup: Identifiable {
    let id: String
    let title: LocalizedText
    let scenes: [PracticeScene]
}

nonisolated struct SceneCatalog {
    let groups: [SceneGroup]

    /// Every scene in display order.
    var scenes: [PracticeScene] {
        self.groups.flatMap(\.scenes)
    }

    init(groups: [SceneGroup]) {
        self.groups = groups.filter { !$0.scenes.isEmpty }
    }

    /// One unnamed group, for tests and previews.
    init(scenes: [PracticeScene]) {
        self.init(groups: [SceneGroup(id: "all", title: LocalizedText(zhHant: "", zhHans: "", en: ""), scenes: scenes)])
    }

    struct Index: Decodable {
        struct Group: Decodable {
            let id: String
            let title: LocalizedText
            let scenes: [SceneID]
        }

        let groups: [Group]
        let released: [SceneID]

        var ids: [SceneID] {
            self.groups.flatMap(\.scenes)
        }
    }

    #if DEBUG
    static let showsDrafts = true
    #else
    static let showsDrafts = false
    #endif

    /// What the screens read. A scene that fails to decode is left out and
    /// logged; `SceneContentTests` decodes them strictly so that never ships.
    static let bundled: SceneCatalog = {
        let log = Logger(subsystem: "app.tuji.ios", category: "scenes")
        let index: Index
        do {
            index = try Self.index(bundle: .main)
        } catch {
            log.error("scene index failed to load: \(error, privacy: .public)")
            return SceneCatalog(groups: [])
        }
        let shown = Set(Self.showsDrafts ? index.ids : index.released)
        return SceneCatalog(groups: index.groups.map { group in
            SceneGroup(id: group.id, title: group.title, scenes: group.scenes.filter(shown.contains).compactMap { id in
                do {
                    return try Self.decode(id, bundle: .main)
                } catch {
                    log.error("scene \(id.rawValue, privacy: .public) failed to load: \(error, privacy: .public)")
                    return nil
                }
            })
        })
    }()

    /// Every scene in the index, drafts included, decoded strictly.
    static func load(bundle: Bundle) throws -> SceneCatalog {
        let index = try self.index(bundle: bundle)
        return try SceneCatalog(groups: index.groups.map { group in
            try SceneGroup(
                id: group.id,
                title: group.title,
                scenes: group.scenes.map { try self.decode($0, bundle: bundle) }
            )
        })
    }

    static func index(bundle: Bundle) throws -> Index {
        try JSONDecoder().decode(Index.self, from: self.data("index.json", bundle: bundle))
    }

    /// The bundled scenes in display order.
    static func ids(bundle: Bundle) throws -> [SceneID] {
        try self.index(bundle: bundle).ids
    }

    func scene(_ id: SceneID) -> PracticeScene? {
        self.scenes.first { $0.id == id }
    }

    static func decode(_ id: SceneID, bundle: Bundle) throws -> PracticeScene {
        try JSONDecoder().decode(PracticeScene.self, from: self.data(id.rawValue + ".json", bundle: bundle))
    }

    private static func data(_ file: String, bundle: Bundle) throws -> Data {
        guard let url = self.resource(file, subdirectories: ["Scenes"], bundle: bundle) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file])
        }
        return try Data(contentsOf: url)
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

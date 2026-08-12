// Where 生成佇列's in-flight jobs live between app launches.
//
// Split from the queue for the same reason as `AtlasCardGenerating`: the on-disk
// half was a hard-coded Application Support path reached through `FileManager`
// inside the queue, so no test could observe what a job had checkpointed. The
// checkpoint is the load-bearing part of the whole pipeline — confirm is a plain
// INSERT, so a resumed run that re-confirms creates a duplicate 自製圖鑑 card —
// and it was the least reachable code in the flow.

import Foundation
import OSLog

/// One capture job as it survives an app kill.
///
/// The thumbnail rides separately rather than as a field: it is display-only,
/// and a job whose photo could not be read back is still a job worth resuming.
struct CaptureJobRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let imageId: String
    let payload: AtlasConfirmPayload
    let lemma: String
    /// Set once confirm succeeds. Its presence *is* the resume rule: a run that
    /// finds one skips confirm and continues from the idempotent tail.
    var itemId: String?
}

/// A restored job: its record, plus the JPEG bytes of the frame the user took if
/// they were still readable.
struct CaptureJobEntry: Equatable {
    let record: CaptureJobRecord
    let thumbnail: Data?
}

@MainActor
protocol CaptureJobJournal {
    func save(_ record: CaptureJobRecord, thumbnail: Data?)
    func remove(_ id: UUID)
    func restore() -> [CaptureJobEntry]
    /// Sign-out. A leftover record would otherwise resume under the next
    /// account's session and surface the previous account's capture there.
    func removeAll()
}

/// The live adapter. Application Support survives app kills and — unlike Caches
/// — is not purged under storage pressure.
@MainActor
struct FileCaptureJobJournal: CaptureJobJournal {
    private let directory: URL
    private let log = Logger(subsystem: "app.tuji.ios", category: "atlas-capture-journal")

    init(directory: URL? = nil) {
        let resolved = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AtlasCaptureQueue", isDirectory: true)
        try? FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        self.directory = resolved
    }

    func save(_ record: CaptureJobRecord, thumbnail: Data?) {
        guard let data = try? JSONEncoder().encode(record) else {
            self.log.error("capture job record failed to encode")
            return
        }
        try? data.write(to: self.jsonURL(record.id))
        if let thumbnail {
            try? thumbnail.write(to: self.thumbURL(record.id))
        }
    }

    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: self.jsonURL(id))
        try? FileManager.default.removeItem(at: self.thumbURL(id))
    }

    func restore() -> [CaptureJobEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: self.directory,
            includingPropertiesForKeys: nil
        )
        else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file),
                      let record = try? JSONDecoder().decode(CaptureJobRecord.self, from: data)
                else { return nil }
                return CaptureJobEntry(
                    record: record,
                    thumbnail: try? Data(contentsOf: self.thumbURL(record.id))
                )
            }
    }

    func removeAll() {
        for entry in self.restore() {
            self.remove(entry.record.id)
        }
    }

    private func jsonURL(_ id: UUID) -> URL {
        self.directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func thumbURL(_ id: UUID) -> URL {
        self.directory.appendingPathComponent("\(id.uuidString).jpg")
    }
}

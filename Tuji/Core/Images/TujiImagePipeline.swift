// Custom Nuke ImagePipeline with explicit memory + disk caps and a
// dedicated DataCache. The shared default has memory cache but no disk
// cache, so images re-download on every cold start. We install our
// pipeline at app launch (TujiApp.init) so every LazyImage picks it up.
//
// Supabase Storage already serves images with `cache-control: public,
// max-age=31536000` + ETag, so disk-cached entries stay valid for a
// year and revalidation is cheap when the year is up.

import Foundation
import Nuke
import OSLog

enum TujiImagePipeline {
    private static let log = Logger(subsystem: "app.tuji.ios", category: "image-pipeline")

    static func install() {
        let dataCache: DataCache?
        do {
            // `name` becomes a subdirectory under NSCachesDirectory.
            let cache = try DataCache(name: "app.tuji.images")
            // 500 MB ceiling. Nuke evicts oldest first when over.
            cache.sizeLimit = 500 * 1024 * 1024
            dataCache = cache
        } catch {
            log.error("DataCache init failed: \(error.localizedDescription, privacy: .public)")
            dataCache = nil
        }

        let pipeline = ImagePipeline {
            $0.dataCache = dataCache
            // Decoded UIImage memory cache. 100 MB caps RAM growth on
            // long scrolling sessions; Nuke evicts under pressure too.
            $0.imageCache = ImageCache(costLimit: 100 * 1024 * 1024, countLimit: 200)
            // Don't double-cache via the system URLCache — DataCache
            // above owns the disk tier.
            let cfg = URLSessionConfiguration.default
            cfg.urlCache = nil
            cfg.timeoutIntervalForRequest = 30
            $0.dataLoader = DataLoader(configuration: cfg)
        }

        ImagePipeline.shared = pipeline
        log.info("custom image pipeline installed (disk cache: \(dataCache != nil, privacy: .public))")
    }
}

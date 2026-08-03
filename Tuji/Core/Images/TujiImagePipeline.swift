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

        ImagePipeline.shared = self.makePipeline(dataCache: dataCache)
        log.info("custom image pipeline installed (disk cache: \(dataCache != nil, privacy: .public))")
    }

    /// Split out from `install()` so a test can exercise the configured
    /// pipeline — cache keys especially — without writing to the global.
    static func makePipeline(dataCache: DataCache?) -> ImagePipeline {
        ImagePipeline(delegate: SignedURLCacheKeys()) {
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
    }
}

/// 自製圖鑑 lives in a *private* Supabase bucket, so the API signs a fresh URL
/// on every response: same object path, a new `token=` each time (verified —
/// two `createSignedUrl` calls one second apart differ). Nuke keys both its
/// memory and its disk cache on the URL, so re-entering 圖鑑管理 looked like a
/// wall of images nobody had ever seen and re-downloaded every thumbnail. The
/// 500 MB DataCache above never scored a hit on a user's own captures.
///
/// The signature authorises the fetch; it doesn't identify the picture. So key
/// on everything *but* the signature.
private final class SignedURLCacheKeys: ImagePipeline.Delegate {
    /// Nuke asks for the key off the main actor, and this target defaults to
    /// MainActor isolation — without `nonisolated` here and on the property
    /// below, only the release (whole-module) build catches it.
    nonisolated func cacheKey(for request: ImageRequest, pipeline _: ImagePipeline) -> String? {
        guard let id = request.url?.signedStorageObjectID else { return nil }
        // Same shape as Nuke's own default key, so adding a processor later
        // can't serve a processed image for an unprocessed request.
        return id + ImageProcessors.Composition(request.processors).identifier
    }
}

extension URL {
    /// Identity of a Supabase-signed storage object: the URL minus the
    /// signature. `nil` for anything else, which leaves Nuke's default key
    /// alone — public images already have stable URLs.
    nonisolated var signedStorageObjectID: String? {
        guard self.path.contains("/storage/v1/object/sign/"),
              var parts = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return nil }
        // Only the token rotates. Anything else in the query (a transform
        // size, say) still describes which picture you get, so it stays.
        let identifying = (parts.queryItems ?? []).filter { $0.name != "token" }
        parts.queryItems = identifying.isEmpty ? nil : identifying
        parts.fragment = nil
        return parts.url?.absoluteString
    }
}

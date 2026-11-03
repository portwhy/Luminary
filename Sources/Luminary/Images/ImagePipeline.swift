import CoreGraphics
import Foundation
import ImageIO

/// A decoded, display-ready bitmap. CGImage is immutable, so sharing across threads is safe.
final class DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
    init(_ cgImage: CGImage) { self.cgImage = cgImage }
}

/// Poster/backdrop loader built for fast-scrolling grids:
/// - **Memory cache** of already-decoded bitmaps, so scrolling back is instant with no flash.
/// - **1 GB disk cache** (URLCache). Jellyfin image URLs carry a content tag, so cached copies never go stale.
/// - **Shared in-flight requests.** Scrolling a card off-screen doesn't cancel its download, so it's
///   ready when you scroll back, and two cards with the same art share one request.
/// - **Retries** for timeouts and 5xx (Jellyfin resizes on first request and can be slow under load).
/// - **Off-main downsampling** to the size actually drawn, so the main thread only ever blits.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private nonisolated let memory: NSCache<NSURL, DecodedImage> = {
        let cache = NSCache<NSURL, DecodedImage>()
        cache.totalCostLimit = 400 * 1024 * 1024
        return cache
    }()
    private var inFlight: [URL: Task<DecodedImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Luminary/Images", isDirectory: true)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 1024 * 1024 * 1024, directory: directory)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    /// Synchronous memory-cache lookup, so views can render a cached image on their very first frame.
    nonisolated func cachedImage(for url: URL) -> DecodedImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Forgets every cached image, in memory and on disk (signing out).
    func clearAll() {
        memory.removeAllObjects()
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    func image(for url: URL, maxPixelSize: Int) async -> DecodedImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let existing = inFlight[url] { return await existing.value }

        let session = self.session
        let task = Task.detached(priority: .userInitiated) { () -> DecodedImage? in
            for attempt in 0..<3 {
                do {
                    let (data, response) = try await session.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                    if (200..<300).contains(status) {
                        return Self.decode(data, maxPixelSize: maxPixelSize)
                    }
                    if status == 404 { return nil } // the item simply has no such image
                } catch {
                    // timeout / connection dropped: fall through to retry
                }
                try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
            }
            return nil
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            memory.setObject(result, forKey: url as NSURL, cost: result.cgImage.bytesPerRow * result.cgImage.height)
        }
        return result
    }

    private static func decode(_ data: Data, maxPixelSize: Int) -> DecodedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true, // decode now, on this background thread
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(image)
    }
}

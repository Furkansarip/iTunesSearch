//
//  ImageDownloader.swift
//  iTunesSearch
//

import UIKit

nonisolated enum ImageDownloaderError: Error, Equatable {
    case invalidImageData
}

/// Downloads images with at most `maxConcurrentDownloads` network fetches in flight.
///
/// Actor isolation alone does not limit concurrency, because the actor is re-entered at every
/// `await fetch(url)`. The limit is a counting semaphore: a fetch may only start while holding a slot,
/// a slot is held until the fetch has actually returned or thrown, and a freed slot is handed directly
/// to the oldest waiter.
actor ImageDownloader {
    typealias Fetch = @Sendable (URL) async throws -> Data

    /// The concurrency limit is per instance, so the app uses this single instance everywhere.
    static let shared = ImageDownloader()

    let maxConcurrentDownloads: Int

    private nonisolated struct Entry {
        let id: UUID
        let task: Task<UIImage, Error>
    }

    private nonisolated struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let fetch: Fetch
    /// NSCache is documented as thread-safe but not annotated `Sendable`.
    private nonisolated(unsafe) let cache = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Entry] = [:]
    private var activeDownloads = 0
    private var waiters: [Waiter] = []
    private var currentSearchID = 0

    init(
        maxConcurrentDownloads: Int = 3,
        cacheCostLimit: Int = 100 * 1024 * 1024,
        fetch: @escaping Fetch = ImageDownloader.urlSessionFetch(session: ImageDownloader.makeSession())
    ) {
        precondition(maxConcurrentDownloads > 0)
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.fetch = fetch
        cache.totalCostLimit = cacheCostLimit
    }

    // MARK: Public API

    /// Synchronous cache lookup (NSCache is thread-safe), so reused cells can show cached images
    /// in the same layout pass instead of flashing a placeholder.
    nonisolated func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Cancelling the caller only stops its wait; the shared download continues for other requesters
    /// until `cancelAll()` is called.
    func image(for url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        return try await task(for: url).value
    }

    func prefetch(_ urls: [URL]) {
        for url in urls where cache.object(forKey: url as NSURL) == nil {
            _ = task(for: url)
        }
    }

    /// Cancels queued and active downloads. Active ones keep their slot until their fetch terminates,
    /// so new downloads may wait briefly but never exceed the limit.
    func cancelAll() {
        for entry in tasks.values {
            entry.task.cancel()
        }
        tasks.removeAll()
    }

    // MARK: Search scoping

    /// Starts search `searchID` by cancelling all downloads. Search IDs must increase monotonically.
    /// Calls carrying an older ID are ignored, so an obsolete task that reaches the actor late
    /// cannot cancel or prefetch on behalf of a search that has already been replaced.
    func beginSearch(_ searchID: Int) {
        guard searchID > currentSearchID else { return }
        currentSearchID = searchID
        cancelAll()
    }

    func prefetch(_ urls: [URL], forSearch searchID: Int) {
        guard searchID == currentSearchID else { return }
        prefetch(urls)
    }

    // MARK: Scheduling

    private func task(for url: URL) -> Task<UIImage, Error> {
        if let entry = tasks[url] {
            return entry.task
        }
        let id = UUID()
        let task = Task { try await self.download(url, id: id) }
        tasks[url] = Entry(id: id, task: task)
        return task
    }

    private func download(_ url: URL, id: UUID) async throws -> UIImage {
        defer {
            if tasks[url]?.id == id {
                tasks[url] = nil
            }
        }

        try await acquireSlot()
        let data: Data
        do {
            defer { releaseSlot() }
            data = try await fetch(url)
        }

        let image = try await Self.decodeImage(data)
        cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        return image
    }

    private func acquireSlot() async throws {
        try Task.checkCancellation()

        if activeDownloads < maxConcurrentDownloads {
            activeDownloads += 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }

        // A slot may have been handed over just before cancellation was processed.
        if Task.isCancelled {
            releaseSlot()
            throw CancellationError()
        }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            activeDownloads -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    // MARK: Helpers

    @concurrent
    private static func decodeImage(_ data: Data) async throws -> UIImage {
        guard let image = UIImage(data: data) else {
            throw ImageDownloaderError.invalidImageData
        }
        return await image.byPreparingForDisplay() ?? image
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }

    nonisolated static func urlSessionFetch(session: URLSession) -> Fetch {
        { url in
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw APIError.httpStatus(httpResponse.statusCode)
            }
            return data
        }
    }
}

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
/// to the oldest high-priority waiter, or the oldest low-priority waiter if there is none.
/// Active downloads are never preempted.
actor ImageDownloader {
    typealias Fetch = @Sendable (URL) async throws -> Data

    nonisolated enum Priority: Sendable {
        /// Visible content.
        case high
        /// Prefetching; may be cancelled with `cancelPrefetch(_:)` while still queued.
        case low
    }

    /// The concurrency limit is per instance, so the app uses this single instance everywhere.
    static let shared = ImageDownloader()

    let maxConcurrentDownloads: Int

    private nonisolated struct Entry {
        let id: UUID
        let task: Task<UIImage, Error>
        /// Only ever raised, so a download needed by visible content is never cancelled as a prefetch.
        var priority: Priority
        var hasSlot = false
    }

    private nonisolated struct Waiter {
        /// The `Entry.id` of the download waiting for a slot.
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let fetch: Fetch
    /// NSCache is documented as thread-safe but not annotated `Sendable`.
    private nonisolated(unsafe) let cache = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Entry] = [:]
    private var activeDownloads = 0
    private var highPriorityWaiters: [Waiter] = []
    private var lowPriorityWaiters: [Waiter] = []
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
    /// until `cancelAll()` is called. A `.high` request promotes a queued prefetch of the same URL
    /// instead of starting a second fetch.
    func image(for url: URL, priority: Priority = .high) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        return try await task(for: url, priority: priority).value
    }

    /// Queues low-priority downloads.
    func prefetch(_ urls: [URL]) {
        for url in urls where cache.object(forKey: url as NSURL) == nil {
            _ = task(for: url, priority: .low)
        }
    }

    /// Cancels downloads that are still low priority and have not started fetching.
    /// Downloads promoted by a visible request, and fetches already in flight, are left alone.
    func cancelPrefetch(_ urls: [URL]) {
        for url in urls {
            guard let entry = tasks[url], entry.priority == .low, !entry.hasSlot else { continue }
            entry.task.cancel()
            tasks[url] = nil
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

    func cancelPrefetch(_ urls: [URL], forSearch searchID: Int) {
        guard searchID == currentSearchID else { return }
        cancelPrefetch(urls)
    }

    // MARK: Scheduling

    private func task(for url: URL, priority: Priority) -> Task<UIImage, Error> {
        if var entry = tasks[url] {
            if priority == .high, entry.priority == .low {
                entry.priority = .high
                tasks[url] = entry
                promoteWaiter(entry.id)
            }
            return entry.task
        }
        let id = UUID()
        let task = Task { try await self.download(url, id: id) }
        tasks[url] = Entry(id: id, task: task, priority: priority)
        return task
    }

    private func download(_ url: URL, id: UUID) async throws -> UIImage {
        defer {
            if tasks[url]?.id == id {
                tasks[url] = nil
            }
        }

        try await acquireSlot(for: url, id: id)
        if tasks[url]?.id == id {
            tasks[url]?.hasSlot = true
        }
        let data: Data
        do {
            defer { releaseSlot() }
            data = try await fetch(url)
        }

        let image = try await Self.decodeImage(data)
        cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        return image
    }

    private func acquireSlot(for url: URL, id: UUID) async throws {
        try Task.checkCancellation()

        // Waiters only exist while every slot is taken, so this cannot overtake queued downloads.
        if activeDownloads < maxConcurrentDownloads {
            activeDownloads += 1
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let waiter = Waiter(id: id, continuation: continuation)
                // Read at enqueue time, so a promotion that happened before this point is honoured.
                if let entry = tasks[url], entry.id == id, entry.priority == .high {
                    highPriorityWaiters.append(waiter)
                } else {
                    lowPriorityWaiters.append(waiter)
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
        if !highPriorityWaiters.isEmpty {
            highPriorityWaiters.removeFirst().continuation.resume()
        } else if !lowPriorityWaiters.isEmpty {
            lowPriorityWaiters.removeFirst().continuation.resume()
        } else {
            activeDownloads -= 1
        }
    }

    private func promoteWaiter(_ id: UUID) {
        guard let index = lowPriorityWaiters.firstIndex(where: { $0.id == id }) else { return }
        highPriorityWaiters.append(lowPriorityWaiters.remove(at: index))
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = highPriorityWaiters.firstIndex(where: { $0.id == id }) {
            highPriorityWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
        } else if let index = lowPriorityWaiters.firstIndex(where: { $0.id == id }) {
            lowPriorityWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
        }
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

//
//  ImageDownloaderTests.swift
//  iTunesSearchTests
//

import UIKit
import XCTest
@testable import iTunesSearch

final class ImageDownloaderTests: XCTestCase {

    // MARK: Concurrency limit and queue

    func testAtMostThreeDownloadsRunAndQueueDrainsCompletely() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let urls = (0..<20).map { testURL("\($0)") }

        await downloader.prefetch(urls)

        try await waitUntil { await network.startedURLs.count == 3 }
        try await settle()
        let startedBeforeCompletion = await network.startedURLs.count
        XCTAssertEqual(startedBeforeCompletion, 3)

        for expectedStarted in 4...urls.count {
            await network.completeNext()
            try await waitUntil { await network.startedURLs.count == expectedStarted }
        }
        for _ in 0..<3 {
            await network.completeNext()
        }
        try await waitUntil { await network.activeCount == 0 }

        let started = await network.startedURLs
        let peak = await network.peakActiveCount
        XCTAssertEqual(started.count, urls.count, "Each URL is fetched exactly once")
        XCTAssertEqual(Set(started), Set(urls))
        XCTAssertEqual(peak, 3)
    }

    // MARK: Merging and caching

    func testSimultaneousRequestsForSameURLAreMerged() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let url = testURL("shared")

        let first = Task { try await downloader.image(for: url) }
        let second = Task { try await downloader.image(for: url) }
        await downloader.prefetch([url, url])
        try await waitUntil { await network.startedURLs.count == 1 }
        try await settle()

        await network.complete(url)
        let firstImage = try await first.value
        let secondImage = try await second.value

        XCTAssertTrue(firstImage === secondImage)
        let startedCount = await network.startedURLs.count
        XCTAssertEqual(startedCount, 1)
    }

    func testCachedImageIsReturnedWithoutNetwork() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let url = testURL("cached")

        let request = Task { try await downloader.image(for: url) }
        try await waitUntil { await network.startedURLs.count == 1 }
        await network.complete(url)
        let downloaded = try await request.value

        let cached = try await downloader.image(for: url)
        await downloader.prefetch([url])
        try await settle()

        XCTAssertTrue(downloaded === cached)
        let startedCount = await network.startedURLs.count
        XCTAssertEqual(startedCount, 1)
    }

    func testCancellingARequesterDoesNotCancelTheSharedDownload() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let url = testURL("reused-cell")

        let requester = Task { try await downloader.image(for: url) }
        try await waitUntil { await network.startedURLs.count == 1 }
        requester.cancel()
        try await settle()

        let cancelled = await network.cancelledURLs
        XCTAssertTrue(cancelled.isEmpty)

        await network.complete(url)
        _ = try? await requester.value
        _ = try await downloader.image(for: url)
        let startedCount = await network.startedURLs.count
        XCTAssertEqual(startedCount, 1, "The completed download was cached")
    }

    // MARK: Failures

    func testFailureIsReportedNotCachedAndDoesNotBlockQueue() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let failing = testURL("failing")
        let others = (0..<3).map { testURL("other-\($0)") }

        let request = Task { try await downloader.image(for: failing) }
        try await waitUntil { await network.startedURLs.contains(failing) }
        await downloader.prefetch(others)
        try await waitUntil { await network.startedURLs.count == 3 }

        await network.fail(failing, with: URLError(.notConnectedToInternet))

        do {
            _ = try await request.value
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        try await waitUntil { await network.startedURLs.count == 4 }

        let retry = Task { try await downloader.image(for: failing) }
        await network.completeNext()
        try await waitUntil { await network.startedURLs.filter { $0 == failing }.count == 2 }
        await network.complete(failing)
        _ = try await retry.value

        let peak = await network.peakActiveCount
        XCTAssertEqual(peak, 3)
    }

    func testInvalidImageDataFailsAndIsNotCached() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let url = testURL("garbage")

        let request = Task { try await downloader.image(for: url) }
        try await waitUntil { await network.startedURLs.count == 1 }
        await network.complete(url, with: Data("not an image".utf8))

        do {
            _ = try await request.value
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertEqual(error as? ImageDownloaderError, .invalidImageData)
        }

        let retry = Task { try await downloader.image(for: url) }
        try await waitUntil { await network.startedURLs.count == 2 }
        await network.complete(url)
        _ = try await retry.value
    }

    // MARK: Cancellation

    func testCancelAllCancelsQueuedRequestsWithoutFetchingThem() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(fetch: network.fetch)
        let urls = (0..<10).map { testURL("\($0)") }

        await downloader.prefetch(urls)
        try await waitUntil { await network.startedURLs.count == 3 }
        let started = await network.startedURLs
        let queuedURL = try XCTUnwrap(urls.first { !started.contains($0) })
        let queuedRequest = Task { try await downloader.image(for: queuedURL) }
        try await settle()

        await downloader.cancelAll()

        do {
            _ = try await queuedRequest.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        try await waitUntil { await network.cancelledURLs.count == 3 }
        await network.failAllPending(with: URLError(.cancelled))
        try await settle()

        let startedAfterCancel = await network.startedURLs.count
        XCTAssertEqual(startedAfterCancel, 3, "Queued requests never reached the network")
    }

    /// Requirement 1: a cancelled active download keeps its slot until it has actually terminated.
    func testCancelledActiveDownloadHoldsSlotUntilTerminated() async throws {
        let network = FakeImageNetwork(respondsToCancellation: false)
        let downloader = ImageDownloader(fetch: network.fetch)
        let searchA = (0..<6).map { testURL("a\($0)") }
        let searchB = (0..<3).map { testURL("b\($0)") }

        await downloader.prefetch(searchA)
        try await waitUntil { await network.startedURLs.count == 3 }

        await downloader.cancelAll()
        await downloader.prefetch(searchB)
        try await waitUntil { await network.cancelledURLs.count == 3 }
        try await settle()

        var started = await network.startedURLs
        var active = await network.activeCount
        XCTAssertEqual(started.count, 3, "No fourth download may start while cancelled ones are still running")
        XCTAssertEqual(active, 3)

        let cancelledURL = try XCTUnwrap(started.first)
        await network.fail(cancelledURL, with: URLError(.cancelled))
        try await waitUntil { await network.startedURLs.count == 4 }
        try await settle()

        started = await network.startedURLs
        active = await network.activeCount
        let peak = await network.peakActiveCount
        XCTAssertEqual(started.count, 4, "Exactly one download replaces the terminated one")
        XCTAssertTrue(searchB.contains(started[3]))
        XCTAssertEqual(active, 3)
        XCTAssertEqual(peak, 3)
    }

    /// Requirement 2: after cancelAll, a new search (including a URL shared with the old one) downloads normally.
    func testSubsequentSearchDownloadsAfterCancelAll() async throws {
        let network = FakeImageNetwork(respondsToCancellation: true)
        let downloader = ImageDownloader(fetch: network.fetch)
        let shared = testURL("shared")
        let searchA = [testURL("a0"), shared, testURL("a2"), testURL("a3"), testURL("a4")]
        let searchB = [shared, testURL("b1"), testURL("b2"), testURL("b3"), testURL("b4")]

        await downloader.prefetch(searchA)
        try await waitUntil { await network.startedURLs.count == 3 }
        await downloader.cancelAll()
        try await waitUntil { await network.activeCount == 0 }

        let requests = searchB.map { url in Task { try await downloader.image(for: url) } }
        try await completeRequests(for: searchB, on: network)

        for request in requests {
            _ = try await request.value
        }
        let peak = await network.peakActiveCount
        XCTAssertLessThanOrEqual(peak, 3)
    }

    /// Requirement 3: the limit holds through repeated cancellation and replacement of requests.
    func testPeakNeverExceedsThreeDuringRapidReplacement() async throws {
        let network = FakeImageNetwork(respondsToCancellation: false)
        let downloader = ImageDownloader(fetch: network.fetch)

        for round in 0..<25 {
            await downloader.prefetch((0..<6).map { testURL("round\(round)-\($0)") })
            if round.isMultiple(of: 3) {
                await network.completeNext()
            }
            if round.isMultiple(of: 5) {
                await network.failAllPending(with: URLError(.cancelled))
            }
            await Task.yield()
            await downloader.cancelAll()

            let active = await network.activeCount
            XCTAssertLessThanOrEqual(active, 3)
        }

        repeat {
            await network.failAllPending(with: URLError(.cancelled))
            try await settle()
        } while await network.activeCount > 0

        let finalSearch = (0..<6).map { testURL("final-\($0)") }
        let requests = finalSearch.map { url in Task { try await downloader.image(for: url) } }
        try await completeRequests(for: finalSearch, on: network)
        for request in requests {
            _ = try await request.value
        }

        let peak = await network.peakActiveCount
        XCTAssertLessThanOrEqual(peak, 3)
    }

    /// Regression: with rapid query changes, an obsolete search task may reach the actor after a newer
    /// one. Its late `beginSearch` and `prefetch` must not cancel or replace the newer search's downloads.
    func testLateCallsFromObsoleteSearchDoNotAffectNewerSearch() async throws {
        let network = FakeImageNetwork()
        let downloader = ImageDownloader(maxConcurrentDownloads: 10, fetch: network.fetch)
        let newer = [testURL("new-0"), testURL("new-1")]
        let obsolete = [testURL("old-0"), testURL("old-1")]

        await downloader.beginSearch(2)
        await downloader.prefetch(newer, forSearch: 2)
        try await waitUntil { await network.startedURLs.count == 2 }

        await downloader.beginSearch(1)
        await downloader.prefetch(obsolete, forSearch: 1)
        try await settle()

        let started = await network.startedURLs
        let cancelled = await network.cancelledURLs
        XCTAssertEqual(Set(started), Set(newer), "The obsolete search must not start downloads")
        XCTAssertTrue(cancelled.isEmpty, "The obsolete search must not cancel newer downloads")
    }

    // MARK: Helpers

    /// Completes each URL once it reaches the network, in whatever order the downloader starts them.
    private func completeRequests(for urls: [URL], on network: FakeImageNetwork) async throws {
        var remaining = Set(urls)
        while !remaining.isEmpty {
            let target = remaining
            try await waitUntil { await network.pendingURLs.contains { target.contains($0) } }
            let pending = await network.pendingURLs
            let url = try XCTUnwrap(pending.first { remaining.contains($0) })
            await network.complete(url)
            remaining.remove(url)
        }
    }
}

//
//  FakeImageNetwork.swift
//  iTunesSearchTests
//

import Foundation
import XCTest
@testable import iTunesSearch

/// A fetch operation fully driven by the test. A request stays in flight until the test completes or
/// fails it. With `respondsToCancellation == false`, a cancelled request also stays in flight,
/// simulating a network operation that takes time to tear down.
actor FakeImageNetwork {
    static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    private struct Request {
        let id: Int
        let url: URL
        let continuation: CheckedContinuation<Data, Error>
    }

    private(set) var startedURLs: [URL] = []
    private(set) var cancelledURLs: [URL] = []
    private(set) var activeCount = 0
    private(set) var peakActiveCount = 0
    private var pending: [Request] = []
    private var nextID = 0
    private let respondsToCancellation: Bool

    init(respondsToCancellation: Bool = false) {
        self.respondsToCancellation = respondsToCancellation
    }

    nonisolated var fetch: ImageDownloader.Fetch {
        { url in try await self.perform(url) }
    }

    var pendingURLs: [URL] { pending.map(\.url) }

    private func perform(_ url: URL) async throws -> Data {
        activeCount += 1
        peakActiveCount = max(peakActiveCount, activeCount)
        startedURLs.append(url)
        defer { activeCount -= 1 }

        let id = nextID
        nextID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.append(Request(id: id, url: url, continuation: continuation))
            }
        } onCancel: {
            Task { await self.handleCancellation(of: id) }
        }
    }

    func complete(_ url: URL, with data: Data = FakeImageNetwork.pngData) {
        resume(url, with: .success(data))
    }

    func fail(_ url: URL, with error: any Error) {
        resume(url, with: .failure(error))
    }

    /// Terminates the oldest pending request, whichever URL it is for.
    func completeNext(with data: Data = FakeImageNetwork.pngData) {
        guard !pending.isEmpty else { return }
        pending.removeFirst().continuation.resume(returning: data)
    }

    func failAllPending(with error: any Error = CancellationError()) {
        let requests = pending
        pending.removeAll()
        requests.forEach { $0.continuation.resume(throwing: error) }
    }

    private func resume(_ url: URL, with result: Result<Data, any Error>) {
        guard let index = pending.firstIndex(where: { $0.url == url }) else {
            XCTFail("No pending request for \(url)")
            return
        }
        pending.remove(at: index).continuation.resume(with: result)
    }

    private func handleCancellation(of id: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        cancelledURLs.append(pending[index].url)
        if respondsToCancellation {
            pending.remove(at: index).continuation.resume(throwing: URLError(.cancelled))
        }
    }
}

/// Polls `condition` until it holds, failing the test after `timeout` instead of hanging.
func waitUntil(
    timeout: Duration = .seconds(3),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            XCTFail("Condition not met within \(timeout)", file: file, line: line)
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// Gives the downloader time to (incorrectly) start more work before a negative assertion.
func settle() async throws {
    try await Task.sleep(for: .milliseconds(150))
}

func testURL(_ name: String) -> URL {
    URL(string: "https://example.com/\(name).png")!
}

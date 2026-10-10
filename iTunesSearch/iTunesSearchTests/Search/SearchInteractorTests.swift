//
//  SearchInteractorTests.swift
//  iTunesSearchTests
//

import XCTest
@testable import iTunesSearch

@MainActor
final class SearchInteractorTests: XCTestCase {

    @MainActor
    private final class PresenterSpy: SearchPresentationLogic {
        var responses: [Search.FetchApps.Response] = []

        var resultIDs: [[Int]] {
            responses.compactMap {
                if case .results(let apps) = $0 { apps.map(\.id) } else { nil }
            }
        }

        func presentSearch(response: Search.FetchApps.Response) {
            responses.append(response)
        }
    }

    private func makeSUT() -> (SearchInteractor, PresenterSpy, FakeSearchTransport, FakeImageNetwork) {
        let transport = FakeSearchTransport()
        let network = FakeImageNetwork()
        let presenter = PresenterSpy()
        let interactor = SearchInteractor(
            presenter: presenter,
            service: ITunesSearchService(client: transport.client),
            imageDownloader: ImageDownloader(maxConcurrentDownloads: 10, fetch: network.fetch),
            debounce: .milliseconds(50)
        )
        return (interactor, presenter, transport, network)
    }

    func testRapidTypingIsDebouncedIntoOneRequest() async throws {
        let (interactor, _, transport, _) = makeSUT()

        interactor.search(request: .init(term: "c"))
        interactor.search(request: .init(term: "ch"))
        interactor.search(request: .init(term: "chess"))

        try await waitUntil { await transport.requestedTerms == ["chess"] }
        try await settle()

        let terms = await transport.requestedTerms
        XCTAssertEqual(terms, ["chess"])
    }

    func testStaleResponseArrivingAfterNewerOneIsIgnored() async throws {
        let (interactor, presenter, transport, _) = makeSUT()

        interactor.search(request: .init(term: "old"))
        try await waitUntil { await transport.requestedTerms == ["old"] }
        interactor.search(request: .init(term: "new"))
        try await waitUntil { await transport.requestedTerms == ["old", "new"] }

        try await transport.respond(to: "new", apps: [(id: 2, screenshots: [])])
        try await waitUntil { await presenter.resultIDs == [[2]] }
        try await transport.respond(to: "old", apps: [(id: 1, screenshots: [])])
        try await settle()

        XCTAssertEqual(presenter.resultIDs, [[2]])
    }

    func testResultsArePresentedAndEveryScreenshotIsPrefetched() async throws {
        let (interactor, presenter, transport, network) = makeSUT()
        let screenshotsA = [testURL("a1"), testURL("a2")]
        let screenshotsB = [testURL("b1"), testURL("b2"), testURL("b3")]

        interactor.search(request: .init(term: "chess"))
        try await waitUntil { await transport.requestedTerms == ["chess"] }
        try await transport.respond(to: "chess", apps: [(id: 1, screenshots: screenshotsA), (id: 2, screenshots: screenshotsB)])

        try await waitUntil { await network.startedURLs.count == 5 }
        let started = await network.startedURLs
        XCTAssertEqual(Set(started), Set(screenshotsA + screenshotsB))
        XCTAssertEqual(presenter.resultIDs, [[1, 2]])
    }

    func testEmptyQueryPresentsIdleAndCancelsDownloads() async throws {
        let (interactor, presenter, transport, network) = makeSUT()

        interactor.search(request: .init(term: "chess"))
        try await waitUntil { await transport.requestedTerms == ["chess"] }
        try await transport.respond(to: "chess", apps: [(id: 1, screenshots: [testURL("1"), testURL("2")])])
        try await waitUntil { await network.startedURLs.count == 2 }

        interactor.search(request: .init(term: "   "))

        try await waitUntil { await network.cancelledURLs.count == 2 }
        guard case .idle = presenter.responses.last else {
            return XCTFail("Expected idle, got \(String(describing: presenter.responses.last))")
        }
    }

    func testErrorIsPresentedButCancellationIsNot() async throws {
        let (interactor, presenter, transport, _) = makeSUT()

        interactor.search(request: .init(term: "offline"))
        try await waitUntil { await transport.requestedTerms == ["offline"] }
        try await transport.fail("offline", with: URLError(.notConnectedToInternet))
        try await waitUntil { await presenter.responses.count == 2 }
        guard case .failure(let error) = presenter.responses.last else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error as? APIError, .transport(URLError(.notConnectedToInternet)))

        interactor.search(request: .init(term: "cancelled"))
        try await waitUntil { await transport.requestedTerms.count == 2 }
        try await transport.fail("cancelled", with: URLError(.cancelled))
        try await settle()

        guard case .loading = presenter.responses.last else {
            return XCTFail("Cancellation must not be presented, got \(String(describing: presenter.responses.last))")
        }
    }
}

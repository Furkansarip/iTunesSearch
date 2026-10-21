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
        var favoriteResponses: [Search.ToggleFavorite.Response] = []

        var resultIDs: [[Int]] {
            responses.compactMap {
                if case .results(let apps, _) = $0 { apps.map(\.id) } else { nil }
            }
        }

        var lastFavoriteIDs: Set<ScreenshotID>? {
            responses.reversed().lazy.compactMap {
                if case .results(_, let favoriteIDs) = $0 { favoriteIDs } else { nil }
            }.first
        }

        func presentSearch(response: Search.FetchApps.Response) {
            responses.append(response)
        }

        func presentFavorite(response: Search.ToggleFavorite.Response) {
            favoriteResponses.append(response)
        }
    }

    @MainActor
    private final class RouterSpy: SearchRoutingLogic {
        var routedURLs: [URL] = []

        func routeToScreenshotPreview(url: URL) {
            routedURLs.append(url)
        }
    }

    private func makeSUT(
        favoriteStore: FavoriteStore = FavoriteStore(),
        router: RouterSpy? = nil
    ) -> (SearchInteractor, PresenterSpy, FakeSearchTransport, FakeImageNetwork) {
        let transport = FakeSearchTransport()
        let network = FakeImageNetwork()
        let presenter = PresenterSpy()
        let interactor = SearchInteractor(
            presenter: presenter,
            router: router,
            service: ITunesSearchService(client: transport.client),
            imageDownloader: ImageDownloader(maxConcurrentDownloads: 10, fetch: network.fetch),
            favoriteStore: favoriteStore,
            debounce: .milliseconds(50)
        )
        return (interactor, presenter, transport, network)
    }

    /// Runs a search for `term` and waits until its results are presented.
    private func showResults(
        _ apps: [(id: Int, screenshots: [URL])],
        for term: String,
        interactor: SearchInteractor,
        presenter: PresenterSpy,
        transport: FakeSearchTransport
    ) async throws {
        let presentedCount = presenter.resultIDs.count
        interactor.search(request: .init(term: term))
        try await waitUntil { await transport.requestedTerms.last == term }
        try await transport.respond(to: term, apps: apps)
        try await waitUntil { await presenter.resultIDs.count == presentedCount + 1 }
    }

    // MARK: Search

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

    func testResultsArePresentedWithoutEagerlyPrefetchingScreenshots() async throws {
        let (interactor, presenter, transport, network) = makeSUT()
        let screenshotsA = [testURL("a1"), testURL("a2")]
        let screenshotsB = [testURL("b1"), testURL("b2"), testURL("b3")]

        try await showResults(
            [(id: 1, screenshots: screenshotsA), (id: 2, screenshots: screenshotsB)],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )
        try await settle()

        XCTAssertEqual(presenter.resultIDs, [[1, 2]])
        let started = await network.startedURLs
        XCTAssertTrue(started.isEmpty, "Screenshots are only fetched once the collection view asks for them")
    }

    func testPrefetchResolvesScreenshotsFromCurrentResults() async throws {
        let (interactor, presenter, transport, network) = makeSUT()
        let screenshotsA = [testURL("a1"), testURL("a2")]
        let screenshotsB = [testURL("b1"), testURL("b2"), testURL("b3")]
        try await showResults(
            [(id: 1, screenshots: screenshotsA), (id: 2, screenshots: screenshotsB)],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )

        interactor.prefetchScreenshots(request: .init(screenshots: [
            ScreenshotID(appID: 1, url: screenshotsA[1]),
            ScreenshotID(appID: 2, url: screenshotsB[0]),
            ScreenshotID(appID: 1, url: screenshotsB[1]),
            ScreenshotID(appID: 99, url: testURL("unknown")),
        ]))

        try await waitUntil { await network.startedURLs.count == 2 }
        try await settle()
        let started = await network.startedURLs
        XCTAssertEqual(Set(started), [screenshotsA[1], screenshotsB[0]], "Invalid references are ignored")
    }

    func testEmptyQueryPresentsIdleAndCancelsDownloads() async throws {
        let (interactor, presenter, transport, network) = makeSUT()
        try await showResults(
            [(id: 1, screenshots: [testURL("1"), testURL("2")])],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )
        interactor.prefetchScreenshots(request: .init(screenshots: [
            ScreenshotID(appID: 1, url: testURL("1")),
            ScreenshotID(appID: 1, url: testURL("2")),
        ]))
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

    // MARK: Favorites

    func testToggleFavoriteTogglesOnlyTheSelectedScreenshot() async throws {
        let store = FavoriteStore()
        let (interactor, presenter, transport, _) = makeSUT(favoriteStore: store)
        let screenshots = [testURL("a1"), testURL("a2"), testURL("a3")]
        try await showResults(
            [(id: 1, screenshots: [testURL("b1")]), (id: 2, screenshots: screenshots)],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )
        let selected = ScreenshotID(appID: 2, url: screenshots[1])

        interactor.toggleFavorite(request: .init(screenshot: ScreenshotID(appID: 99, url: screenshots[1])))
        interactor.toggleFavorite(request: .init(screenshot: selected))
        try await waitUntil { await presenter.favoriteResponses.count == 1 }
        try await settle()

        XCTAssertEqual(presenter.favoriteResponses.count, 1, "Screenshots outside the results are ignored")
        let response = try XCTUnwrap(presenter.favoriteResponses.first)
        XCTAssertEqual(response.app.id, 2)
        XCTAssertEqual(response.appIndex, 1)
        XCTAssertEqual(response.screenshotIndex, 1)
        XCTAssertTrue(response.isFavorite)
        let favorites = await store.favoriteIDs()
        XCTAssertEqual(favorites, [selected], "Other screenshots of the same app are unchanged")
    }

    func testScreenshotsOfTheSameAppAreFavoritedIndependently() async throws {
        let store = FavoriteStore()
        let (interactor, presenter, transport, _) = makeSUT(favoriteStore: store)
        let screenshots = [testURL("a1"), testURL("a2")]
        try await showResults(
            [(id: 1, screenshots: screenshots)],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )
        let first = ScreenshotID(appID: 1, url: screenshots[0])
        let second = ScreenshotID(appID: 1, url: screenshots[1])

        interactor.toggleFavorite(request: .init(screenshot: first))
        try await waitUntil { await presenter.favoriteResponses.count == 1 }
        interactor.toggleFavorite(request: .init(screenshot: second))
        try await waitUntil { await presenter.favoriteResponses.count == 2 }
        interactor.toggleFavorite(request: .init(screenshot: first))
        try await waitUntil { await presenter.favoriteResponses.count == 3 }

        XCTAssertEqual(presenter.favoriteResponses.map(\.isFavorite), [true, true, false])
        let favorites = await store.favoriteIDs()
        XCTAssertEqual(favorites, [second], "Toggling twice restores the original state")
    }

    func testFavoritesPersistAcrossSearches() async throws {
        let store = FavoriteStore()
        let (interactor, presenter, transport, _) = makeSUT(favoriteStore: store)
        let favorite = ScreenshotID(appID: 2, url: testURL("b1"))
        try await showResults(
            [(id: 1, screenshots: [testURL("a1")]), (id: 2, screenshots: [favorite.url])],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )
        XCTAssertEqual(presenter.lastFavoriteIDs, [])

        interactor.toggleFavorite(request: .init(screenshot: favorite))
        try await waitUntil { await presenter.favoriteResponses.count == 1 }

        try await showResults(
            [(id: 2, screenshots: [favorite.url]), (id: 3, screenshots: [])],
            for: "puzzle", interactor: interactor, presenter: presenter, transport: transport
        )
        XCTAssertEqual(presenter.lastFavoriteIDs, [favorite])
    }

    // MARK: Routing

    func testSelectingScreenshotRoutesToItsURL() async throws {
        let router = RouterSpy()
        let (interactor, presenter, transport, _) = makeSUT(router: router)
        let screenshots = [testURL("a1"), testURL("a2")]
        try await showResults(
            [(id: 1, screenshots: []), (id: 2, screenshots: screenshots)],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )

        interactor.selectScreenshot(request: .init(screenshot: ScreenshotID(appID: 2, url: screenshots[1])))

        XCTAssertEqual(router.routedURLs, [screenshots[1]])
    }

    func testInvalidOrStaleSelectionDoesNotRoute() async throws {
        let router = RouterSpy()
        let (interactor, presenter, transport, _) = makeSUT(router: router)
        let valid = ScreenshotID(appID: 1, url: testURL("a1"))

        interactor.selectScreenshot(request: .init(screenshot: valid))

        try await showResults(
            [(id: 1, screenshots: [valid.url]), (id: 2, screenshots: [])],
            for: "chess", interactor: interactor, presenter: presenter, transport: transport
        )
        interactor.selectScreenshot(request: .init(screenshot: ScreenshotID(appID: 1, url: testURL("missing"))))
        interactor.selectScreenshot(request: .init(screenshot: ScreenshotID(appID: 2, url: valid.url)))
        interactor.selectScreenshot(request: .init(screenshot: ScreenshotID(appID: 99, url: valid.url)))

        interactor.search(request: .init(term: "puzzle"))
        interactor.selectScreenshot(request: .init(screenshot: valid))

        XCTAssertTrue(router.routedURLs.isEmpty)
    }
}

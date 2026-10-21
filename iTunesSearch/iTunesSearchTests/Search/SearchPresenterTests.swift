//
//  SearchPresenterTests.swift
//  iTunesSearchTests
//

import XCTest
@testable import iTunesSearch

@MainActor
final class SearchPresenterTests: XCTestCase {

    @MainActor
    private final class DisplaySpy: SearchDisplayLogic {
        var viewModels: [Search.FetchApps.ViewModel] = []
        var favoriteViewModels: [Search.ToggleFavorite.ViewModel] = []

        func displaySearch(viewModel: Search.FetchApps.ViewModel) {
            viewModels.append(viewModel)
        }

        func displayFavorite(viewModel: Search.ToggleFavorite.ViewModel) {
            favoriteViewModels.append(viewModel)
        }
    }

    /// `async` because releasing a main-actor class with an implicit isolated deinit inside a
    /// synchronous XCTest method crashes in the Swift runtime (TaskLocal::StopLookupScope).
    func testResponsesMapToViewModels() async {
        let presenter = SearchPresenter()
        let display = DisplaySpy()
        presenter.viewController = display
        let withScreenshots = AppResult(id: 1, name: "Chess", developer: "Dev", screenshotURLs: [testURL("1")])
        let withoutScreenshots = AppResult(id: 2, name: "iPad Only", developer: "Dev", screenshotURLs: [])

        presenter.presentSearch(response: .loading)
        presenter.presentSearch(response: .results([withScreenshots, withoutScreenshots], favoriteIDs: []))
        presenter.presentSearch(response: .results([], favoriteIDs: []))
        presenter.presentSearch(response: .failure(APIError.httpStatus(429)))
        presenter.presentSearch(response: .idle)

        XCTAssertEqual(display.viewModels, [
            .loading,
            .results([
                .init(id: 1, title: "Chess", subtitle: "Dev", screenshots: [
                    .init(id: ScreenshotID(appID: 1, url: testURL("1")), isFavorite: false, accessibilityLabel: "Chess screenshot 1 of 1"),
                ]),
                .init(id: 2, title: "iPad Only", subtitle: "Dev", screenshots: []),
            ]),
            .empty(message: "No apps match your search."),
            .error(message: "Too many searches. Please wait a moment and try again."),
            .idle,
        ])
    }

    func testFavoriteStateIsMappedPerScreenshot() async {
        let presenter = SearchPresenter()
        let display = DisplaySpy()
        presenter.viewController = display
        let chess = AppResult(id: 1, name: "Chess", developer: "Dev", screenshotURLs: [testURL("1"), testURL("2")])
        let first = ScreenshotID(appID: 1, url: testURL("1"))
        let second = ScreenshotID(appID: 1, url: testURL("2"))

        presenter.presentSearch(response: .results([chess], favoriteIDs: [second, ScreenshotID(appID: 9, url: testURL("1"))]))
        presenter.presentFavorite(response: .init(app: chess, appIndex: 0, screenshotIndex: 0, isFavorite: true))

        XCTAssertEqual(display.viewModels, [
            .results([
                .init(id: 1, title: "Chess", subtitle: "Dev", screenshots: [
                    .init(id: first, isFavorite: false, accessibilityLabel: "Chess screenshot 1 of 2"),
                    .init(id: second, isFavorite: true, accessibilityLabel: "Chess screenshot 2 of 2"),
                ]),
            ]),
        ])
        XCTAssertEqual(display.favoriteViewModels, [
            .init(
                sectionIndex: 0,
                itemIndex: 0,
                item: .init(id: first, isFavorite: true, accessibilityLabel: "Chess screenshot 1 of 2")
            ),
        ])
    }
}

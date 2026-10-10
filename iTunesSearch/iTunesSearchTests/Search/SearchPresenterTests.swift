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

        func displaySearch(viewModel: Search.FetchApps.ViewModel) {
            viewModels.append(viewModel)
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
        presenter.presentSearch(response: .results([withScreenshots, withoutScreenshots]))
        presenter.presentSearch(response: .results([]))
        presenter.presentSearch(response: .failure(APIError.httpStatus(429)))
        presenter.presentSearch(response: .idle)

        XCTAssertEqual(display.viewModels, [
            .loading,
            .results([
                .init(id: 1, title: "Chess", subtitle: "Dev", screenshotURLs: [testURL("1")]),
                .init(id: 2, title: "iPad Only", subtitle: "Dev", screenshotURLs: []),
            ]),
            .empty(message: "No apps match your search."),
            .error(message: "Too many searches. Please wait a moment and try again."),
            .idle,
        ])
    }
}

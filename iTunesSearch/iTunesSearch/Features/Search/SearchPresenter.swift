//
//  SearchPresenter.swift
//  iTunesSearch
//

import Foundation

protocol SearchPresentationLogic: AnyObject {
    func presentSearch(response: Search.FetchApps.Response)
    func presentFavorite(response: Search.ToggleFavorite.Response)
}

protocol SearchDisplayLogic: AnyObject {
    func displaySearch(viewModel: Search.FetchApps.ViewModel)
    func displayFavorite(viewModel: Search.ToggleFavorite.ViewModel)
}

final class SearchPresenter: SearchPresentationLogic {
    weak var viewController: SearchDisplayLogic?

    func presentSearch(response: Search.FetchApps.Response) {
        viewController?.displaySearch(viewModel: viewModel(for: response))
    }

    func presentFavorite(response: Search.ToggleFavorite.Response) {
        viewController?.displayFavorite(viewModel: .init(
            sectionIndex: response.appIndex,
            itemIndex: response.screenshotIndex,
            item: item(for: response.app, at: response.screenshotIndex, isFavorite: response.isFavorite)
        ))
    }

    private func viewModel(for response: Search.FetchApps.Response) -> Search.FetchApps.ViewModel {
        switch response {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .results(let apps, _) where apps.isEmpty:
            return .empty(message: "No apps match your search.")
        case .results(let apps, let favoriteIDs):
            return .results(apps.map { section(for: $0, favoriteIDs: favoriteIDs) })
        case .failure(let error):
            return .error(message: message(for: error))
        }
    }

    private func section(for app: AppResult, favoriteIDs: Set<ScreenshotID>) -> Search.FetchApps.AppSection {
        Search.FetchApps.AppSection(
            id: app.id,
            title: app.name,
            subtitle: app.developer,
            screenshots: app.screenshotURLs.indices.map { index in
                item(for: app, at: index, isFavorite: favoriteIDs.contains(ScreenshotID(appID: app.id, url: app.screenshotURLs[index])))
            },
            usesLandscapeScreenshots: app.screenshotURLs.first.map(isLandscape) ?? false
        )
    }

    private func item(for app: AppResult, at index: Int, isFavorite: Bool) -> Search.ScreenshotItemViewModel {
        Search.ScreenshotItemViewModel(
            id: ScreenshotID(appID: app.id, url: app.screenshotURLs[index]),
            isFavorite: isFavorite,
            accessibilityLabel: "\(app.name) screenshot \(index + 1) of \(app.screenshotURLs.count)"
        )
    }

    /// iTunes screenshot URLs end in a size component such as `406x228bb.jpg`.
    /// Unknown formats fall back to portrait, the most common orientation.
    private func isLandscape(_ url: URL) -> Bool {
        guard let match = url.lastPathComponent.firstMatch(of: /^(\d+)x(\d+)/),
              let width = Int(match.1), let height = Int(match.2)
        else { return false }
        return width > height
    }

    private func message(for error: any Error) -> String {
        switch error as? APIError {
        case .transport(let urlError) where [.notConnectedToInternet, .networkConnectionLost].contains(urlError.code):
            return "No internet connection. Check your connection and try again."
        case .httpStatus(403), .httpStatus(429):
            return "Too many searches. Please wait a moment and try again."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

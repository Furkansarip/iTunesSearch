//
//  SearchPresenter.swift
//  iTunesSearch
//

import Foundation

protocol SearchPresentationLogic: AnyObject {
    func presentSearch(response: Search.FetchApps.Response)
}

protocol SearchDisplayLogic: AnyObject {
    func displaySearch(viewModel: Search.FetchApps.ViewModel)
}

final class SearchPresenter: SearchPresentationLogic {
    weak var viewController: SearchDisplayLogic?

    func presentSearch(response: Search.FetchApps.Response) {
        viewController?.displaySearch(viewModel: viewModel(for: response))
    }

    private func viewModel(for response: Search.FetchApps.Response) -> Search.FetchApps.ViewModel {
        switch response {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .results(let apps) where apps.isEmpty:
            return .empty(message: "No apps match your search.")
        case .results(let apps):
            return .results(apps.map {
                Search.FetchApps.AppSection(
                    id: $0.id,
                    title: $0.name,
                    subtitle: $0.developer,
                    screenshotURLs: $0.screenshotURLs,
                    usesLandscapeScreenshots: $0.screenshotURLs.first.map(isLandscape) ?? false
                )
            })
        case .failure(let error):
            return .error(message: message(for: error))
        }
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

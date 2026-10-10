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
        case .results(let apps):
            let sections = apps
                .filter { !$0.screenshotURLs.isEmpty }
                .map { Search.FetchApps.AppSection(id: $0.id, title: $0.name, subtitle: $0.developer, screenshotURLs: $0.screenshotURLs) }
            return sections.isEmpty ? .empty(message: "No apps with screenshots found.") : .results(sections)
        case .failure(let error):
            return .error(message: message(for: error))
        }
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

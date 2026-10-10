//
//  SearchInteractor.swift
//  iTunesSearch
//

import Foundation

protocol SearchBusinessLogic: AnyObject {
    func search(request: Search.FetchApps.Request)
    /// Re-runs the current term immediately, even if it has not changed.
    func retry()
}

final class SearchInteractor: SearchBusinessLogic {
    private let presenter: SearchPresentationLogic
    private let service: ITunesSearchService
    private let imageDownloader: ImageDownloader
    private let debounce: Duration

    private var currentTerm = ""
    private var requestID = 0
    private var searchTask: Task<Void, Never>?

    init(
        presenter: SearchPresentationLogic,
        service: ITunesSearchService = ITunesSearchService(),
        imageDownloader: ImageDownloader = .shared,
        debounce: Duration = .milliseconds(350)
    ) {
        self.presenter = presenter
        self.service = service
        self.imageDownloader = imageDownloader
        self.debounce = debounce
    }

    deinit {
        searchTask?.cancel()
    }

    func search(request: Search.FetchApps.Request) {
        let term = request.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term != currentTerm else { return }

        currentTerm = term
        startSearch(debounce: debounce)
    }

    func retry() {
        startSearch(debounce: .zero)
    }

    private func startSearch(debounce: Duration) {
        let term = currentTerm
        requestID += 1
        let id = requestID
        searchTask?.cancel()

        guard !term.isEmpty else {
            searchTask = Task { [imageDownloader] in await imageDownloader.beginSearch(id) }
            presenter.presentSearch(response: .idle)
            return
        }

        presenter.presentSearch(response: .loading)
        searchTask = Task { [weak self, imageDownloader, service] in
            // Downloader calls carry `id`, so they are ignored if they arrive after a newer search's.
            await imageDownloader.beginSearch(id)
            do {
                try await Task.sleep(for: debounce)
                let apps = try await service.search(term: term)

                // `requestID` is checked after every suspension, so a response that arrives
                // despite cancellation can never replace newer state.
                guard let self, self.requestID == id else { return }
                await imageDownloader.prefetch(apps.flatMap(\.screenshotURLs), forSearch: id)
                guard self.requestID == id else { return }
                self.presenter.presentSearch(response: .results(apps))
            } catch is CancellationError {
            } catch {
                guard let self, self.requestID == id else { return }
                self.presenter.presentSearch(response: .failure(error))
            }
        }
    }
}

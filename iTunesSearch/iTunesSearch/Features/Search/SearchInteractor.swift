//
//  SearchInteractor.swift
//  iTunesSearch
//

import Foundation

protocol SearchBusinessLogic: AnyObject {
    func search(request: Search.FetchApps.Request)
    /// Re-runs the current term immediately, even if it has not changed.
    func retry()
    func toggleFavorite(request: Search.ToggleFavorite.Request)
    func selectScreenshot(request: Search.SelectScreenshot.Request)
    func prefetchScreenshots(request: Search.PrefetchScreenshots.Request)
    func cancelScreenshotPrefetching(request: Search.PrefetchScreenshots.Request)
}

final class SearchInteractor: SearchBusinessLogic {
    private let presenter: SearchPresentationLogic
    private let router: SearchRoutingLogic?
    private let service: ITunesSearchService
    private let imageDownloader: ImageDownloader
    private let favoriteStore: any FavoriteStoring
    private let debounce: Duration

    private var currentTerm = ""
    private var requestID = 0
    private var searchTask: Task<Void, Never>?
    private var apps: [AppResult] = []

    init(
        presenter: SearchPresentationLogic,
        router: SearchRoutingLogic? = nil,
        service: ITunesSearchService = ITunesSearchService(),
        imageDownloader: ImageDownloader = .shared,
        favoriteStore: any FavoriteStoring = FavoriteStore.shared,
        debounce: Duration = .milliseconds(350)
    ) {
        self.presenter = presenter
        self.router = router
        self.service = service
        self.imageDownloader = imageDownloader
        self.favoriteStore = favoriteStore
        self.debounce = debounce
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: Search

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
        apps = []

        guard !term.isEmpty else {
            searchTask = Task { [imageDownloader] in await imageDownloader.beginSearch(id) }
            presenter.presentSearch(response: .idle)
            return
        }

        presenter.presentSearch(response: .loading)
        searchTask = Task { [weak self, imageDownloader, service, favoriteStore] in
            // Downloader calls carry `id`, so they are ignored if they arrive after a newer search's.
            await imageDownloader.beginSearch(id)
            do {
                try await Task.sleep(for: debounce)
                let apps = try await service.search(term: term)

                // `requestID` is checked after every suspension, so a response that arrives
                // despite cancellation can never replace newer state.
                let favoriteIDs = await favoriteStore.favoriteIDs()
                guard let self, self.requestID == id else { return }
                self.apps = apps
                self.presenter.presentSearch(response: .results(apps, favoriteIDs: favoriteIDs))
            } catch is CancellationError {
            } catch {
                guard let self, self.requestID == id else { return }
                self.presenter.presentSearch(response: .failure(error))
            }
        }
    }

    // MARK: Favorites

    func toggleFavorite(request: Search.ToggleFavorite.Request) {
        let screenshot = request.screenshot
        guard position(of: screenshot) != nil else { return }

        Task { [weak self, favoriteStore] in
            let isFavorite = await favoriteStore.toggle(screenshot)
            // The results may have changed while the store was updating.
            guard let self, let (appIndex, screenshotIndex) = self.position(of: screenshot) else { return }
            self.presenter.presentFavorite(response: .init(
                app: self.apps[appIndex],
                appIndex: appIndex,
                screenshotIndex: screenshotIndex,
                isFavorite: isFavorite
            ))
        }
    }

    // MARK: Screenshots

    func selectScreenshot(request: Search.SelectScreenshot.Request) {
        guard position(of: request.screenshot) != nil else { return }
        router?.routeToScreenshotPreview(url: request.screenshot.url)
    }

    func prefetchScreenshots(request: Search.PrefetchScreenshots.Request) {
        let urls = validURLs(request.screenshots)
        guard !urls.isEmpty else { return }
        let id = requestID
        Task { [imageDownloader] in await imageDownloader.prefetch(urls, forSearch: id) }
    }

    func cancelScreenshotPrefetching(request: Search.PrefetchScreenshots.Request) {
        let urls = validURLs(request.screenshots)
        guard !urls.isEmpty else { return }
        let id = requestID
        Task { [imageDownloader] in await imageDownloader.cancelPrefetch(urls, forSearch: id) }
    }

    private func validURLs(_ screenshots: [ScreenshotID]) -> [URL] {
        screenshots.filter { position(of: $0) != nil }.map(\.url)
    }

    /// Where `screenshot` is in the current results, or nil if it is not part of them.
    private func position(of screenshot: ScreenshotID) -> (appIndex: Int, screenshotIndex: Int)? {
        guard let appIndex = apps.firstIndex(where: { $0.id == screenshot.appID }),
              let screenshotIndex = apps[appIndex].screenshotURLs.firstIndex(of: screenshot.url)
        else { return nil }
        return (appIndex, screenshotIndex)
    }
}

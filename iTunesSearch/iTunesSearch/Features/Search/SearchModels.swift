//
//  SearchModels.swift
//  iTunesSearch
//

import Foundation

enum Search {
    enum FetchApps {
        struct Request {
            let term: String
        }

        enum Response {
            case idle
            case loading
            case results([AppResult], favoriteIDs: Set<ScreenshotID>)
            case failure(any Error)
        }

        enum ViewModel: Equatable {
            case idle
            case loading
            case results([AppSection])
            case empty(message: String)
            case error(message: String)
        }

        struct AppSection: Equatable {
            let id: Int
            let title: String
            let subtitle: String
            var screenshots: [ScreenshotItemViewModel]
            var usesLandscapeScreenshots = false
        }
    }

    struct ScreenshotItemViewModel: Equatable {
        let id: ScreenshotID
        let isFavorite: Bool
        let accessibilityLabel: String

        var imageURL: URL { id.url }
    }

    enum ToggleFavorite {
        struct Request {
            let screenshot: ScreenshotID
        }

        struct Response {
            let app: AppResult
            /// Positions in the presented results, which map one-to-one to sections and items.
            let appIndex: Int
            let screenshotIndex: Int
            let isFavorite: Bool
        }

        struct ViewModel: Equatable {
            let sectionIndex: Int
            let itemIndex: Int
            let item: ScreenshotItemViewModel
        }
    }

    enum SelectScreenshot {
        struct Request {
            let screenshot: ScreenshotID
        }
    }

    enum PrefetchScreenshots {
        struct Request {
            let screenshots: [ScreenshotID]
        }
    }
}

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
            case results([AppResult])
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
            let screenshotURLs: [URL]
            var usesLandscapeScreenshots = false
        }
    }
}

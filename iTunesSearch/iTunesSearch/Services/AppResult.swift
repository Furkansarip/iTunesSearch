//
//  AppResult.swift
//  iTunesSearch
//

import Foundation

nonisolated struct AppResult: Equatable, Sendable {
    let id: Int
    let name: String
    let developer: String
    let screenshotURLs: [URL]
}

nonisolated struct ScreenshotID: Hashable, Sendable {
    let appID: Int
    let url: URL
}

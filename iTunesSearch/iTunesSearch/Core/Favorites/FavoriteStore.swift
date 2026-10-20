//
//  FavoriteStore.swift
//  iTunesSearch
//

import Foundation

protocol FavoriteStoring: Actor {
    func toggle(_ screenshot: ScreenshotID) -> Bool
    func favoriteIDs() -> Set<ScreenshotID>
}

/// Shared, in-memory favorite screenshots for the app session.
actor FavoriteStore: FavoriteStoring {
    static let shared = FavoriteStore()

    private var ids: Set<ScreenshotID> = []

    func toggle(_ screenshot: ScreenshotID) -> Bool {
        if ids.remove(screenshot) != nil {
            return false
        }
        ids.insert(screenshot)
        return true
    }

    func favoriteIDs() -> Set<ScreenshotID> {
        ids
    }
}

//
//  iTunesSearchUITests.swift
//  iTunesSearchUITests
//
//  Created by Furkan Sarı on 10.10.2026.
//

import XCTest

final class iTunesSearchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

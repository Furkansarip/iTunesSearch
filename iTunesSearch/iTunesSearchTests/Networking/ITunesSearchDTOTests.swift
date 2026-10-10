//
//  ITunesSearchDTOTests.swift
//  iTunesSearchTests
//

import XCTest
@testable import iTunesSearch

final class ITunesSearchDTOTests: XCTestCase {

    private func decode(_ json: String) throws -> ITunesSearchResponseDTO {
        try JSONDecoder().decode(ITunesSearchResponseDTO.self, from: Data(json.utf8))
    }

    func testDecodesRealisticResponseIgnoringUnusedFields() throws {
        let json = """
        {
          "resultCount": 2,
          "results": [
            {
              "kind": "software",
              "trackId": 329218549,
              "trackName": "Chess.com - Play and Learn",
              "artistName": "Chess.com",
              "averageUserRating": 4.8,
              "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg",
              "screenshotUrls": [
                "https://is1-ssl.mzstatic.com/image/thumb/a/392x696bb.png",
                "https://is1-ssl.mzstatic.com/image/thumb/b/392x696bb.png"
              ],
              "ipadScreenshotUrls": ["https://is1-ssl.mzstatic.com/image/thumb/c/576x768bb.png"]
            },
            {
              "trackId": 2,
              "trackName": "Second",
              "artistName": "Other",
              "screenshotUrls": []
            }
          ]
        }
        """

        let apps = try decode(json).results.map { $0.toDomain() }

        XCTAssertEqual(apps, [
            AppResult(
                id: 329218549,
                name: "Chess.com - Play and Learn",
                developer: "Chess.com",
                screenshotURLs: [
                    URL(string: "https://is1-ssl.mzstatic.com/image/thumb/a/392x696bb.png")!,
                    URL(string: "https://is1-ssl.mzstatic.com/image/thumb/b/392x696bb.png")!,
                ]
            ),
            AppResult(id: 2, name: "Second", developer: "Other", screenshotURLs: []),
        ])
    }

    func testMissingScreenshotUrlsBecomesEmptyArray() throws {
        let app = try decode(#"{"results": [{"trackId": 1, "trackName": "A"}]}"#).results[0]

        XCTAssertEqual(app.screenshotUrls, [])
        XCTAssertEqual(app.toDomain().developer, "")
    }

    func testNullScreenshotUrlsBecomesEmptyArray() throws {
        let app = try decode(#"{"results": [{"trackId": 1, "trackName": "A", "screenshotUrls": null}]}"#).results[0]

        XCTAssertEqual(app.screenshotUrls, [])
    }

    func testNullEntriesInsideScreenshotUrlsAreDropped() throws {
        let json = #"{"results": [{"trackId": 1, "trackName": "A", "screenshotUrls": [null, "https://example.com/a.png"]}]}"#

        let app = try decode(json).results[0].toDomain()

        XCTAssertEqual(app.screenshotURLs, [URL(string: "https://example.com/a.png")!])
    }

    func testEmptyResults() throws {
        XCTAssertTrue(try decode(#"{"resultCount": 0, "results": []}"#).results.isEmpty)
    }

    func testMissingOrInvalidResultsArrayFailsDecoding() {
        XCTAssertThrowsError(try decode(#"{"resultCount": 0}"#))
        XCTAssertThrowsError(try decode(#"{"results": {"trackId": 1}}"#))
        XCTAssertThrowsError(try decode(#"{"results": null}"#))
    }

    // MARK: Screenshot URL filtering

    func testMalformedAndUnsupportedScreenshotURLsAreFiltered() {
        let rejected = [
            "",
            "   ",
            "not a url",
            "/relative/path.png",
            "http://example.com/insecure.png",
            "ftp://example.com/file.png",
            "data:image/png;base64,AAAA",
            "https://",
        ]

        for string in rejected {
            XCTAssertNil(ITunesAppDTO.screenshotURL(from: string), "Expected \"\(string)\" to be rejected")
        }
    }

    func testValidScreenshotURLsAreAcceptedAndTrimmed() {
        XCTAssertEqual(
            ITunesAppDTO.screenshotURL(from: " https://is1-ssl.mzstatic.com/a/392x696bb.png\n"),
            URL(string: "https://is1-ssl.mzstatic.com/a/392x696bb.png")
        )
        XCTAssertEqual(
            ITunesAppDTO.screenshotURL(from: "HTTPS://example.com/a.png")?.host(),
            "example.com"
        )
    }

    func testMappingPreservesScreenshotOrderAndDropsOnlyInvalidEntries() throws {
        let json = """
        {"results": [{"trackId": 1, "trackName": "A", "screenshotUrls": [
            "https://example.com/1.png", "bad url", "http://example.com/2.png", "https://example.com/3.png"
        ]}]}
        """

        let app = try decode(json).results[0].toDomain()

        XCTAssertEqual(app.screenshotURLs.map(\.absoluteString), [
            "https://example.com/1.png",
            "https://example.com/3.png",
        ])
    }
}

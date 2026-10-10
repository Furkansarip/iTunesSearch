//
//  ITunesSearchServiceTests.swift
//  iTunesSearchTests
//

import XCTest
@testable import iTunesSearch

final class ITunesSearchServiceTests: XCTestCase {

    // MARK: URL construction

    func testURLContainsTermMediaAndLimit() throws {
        let url = try XCTUnwrap(ITunesSearchService.makeURL(term: "chess"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "itunes.apple.com")
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "term", value: "chess"),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "limit", value: "25"),
        ])
    }

    func testPlusIsEncodedSoServerDoesNotReadItAsSpace() throws {
        let url = try XCTUnwrap(ITunesSearchService.makeURL(term: "c++ notes"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)

        XCTAssertTrue(query.hasPrefix("term=c%2B%2B%20notes&"), query)
        XCTAssertFalse(query.contains("+"))
    }

    func testReservedQueryCharactersAreEncoded() throws {
        let url = try XCTUnwrap(ITunesSearchService.makeURL(term: "a&media=music#x"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.count, 3)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "media" })?.value, "software")
        XCTAssertNil(components.fragment)
    }

    func testSpecialCharactersRoundTrip() throws {
        let terms = ["c++", "hello world", "şğüİıöç ÇĞÜŞÖ", "🎮 games", "  padded  ", "日本語"]

        for term in terms {
            let url = try XCTUnwrap(ITunesSearchService.makeURL(term: term), term)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "term" })?.value, term)
        }
    }

    // MARK: Search

    func testSearchSendsExpectedRequestAndMapsResults() async throws {
        let expectedURL = ITunesSearchService.makeURL(term: "chess")
        let client = APIClient { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(request.httpMethod, "GET")
            let body = """
            {"resultCount": 1, "results": [{
                "trackId": 1, "trackName": "Chess", "artistName": "Dev",
                "screenshotUrls": ["https://example.com/1.png", "http://example.com/2.png"]
            }]}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        let results = try await ITunesSearchService(client: client).search(term: "chess")

        XCTAssertEqual(results, [
            AppResult(id: 1, name: "Chess", developer: "Dev", screenshotURLs: [URL(string: "https://example.com/1.png")!]),
        ])
    }

    func testSearchSkipsMalformedEntriesAndKeepsValidOnes() async throws {
        let body = """
        {"resultCount": 5, "results": [
            {"trackId": 1, "trackName": "Valid One", "artistName": "Dev"},
            {"trackName": "Missing id"},
            {"trackId": 3},
            "not an object",
            {"trackId": 5, "trackName": "Valid Two", "screenshotUrls": ["https://example.com/5.png"]}
        ]}
        """
        let service = ITunesSearchService(client: StubTransport.client(body: body))

        let results = try await service.search(term: "chess")

        XCTAssertEqual(results, [
            AppResult(id: 1, name: "Valid One", developer: "Dev", screenshotURLs: []),
            AppResult(id: 5, name: "Valid Two", developer: "", screenshotURLs: [URL(string: "https://example.com/5.png")!]),
        ])
    }

    func testSearchPropagatesHTTPStatusError() async {
        let service = ITunesSearchService(client: StubTransport.client(status: 403, body: ""))

        do {
            _ = try await service.search(term: "chess")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .httpStatus(403))
        }
    }
}

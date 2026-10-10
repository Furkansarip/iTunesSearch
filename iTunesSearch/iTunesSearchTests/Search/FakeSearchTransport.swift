//
//  FakeSearchTransport.swift
//  iTunesSearchTests
//

import Foundation
import XCTest
@testable import iTunesSearch

/// Holds every search request until the test responds. Cancellation is deliberately ignored,
/// so late responses still arrive and stale-response protection is exercised.
actor FakeSearchTransport {
    private struct Request {
        let term: String
        let url: URL
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
    }

    private(set) var requestedTerms: [String] = []
    private var pending: [Request] = []

    nonisolated var client: APIClient {
        APIClient { request in try await self.perform(request) }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "term" }?.value ?? ""
        requestedTerms.append(term)
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(Request(term: term, url: url, continuation: continuation))
        }
    }

    /// `apps` maps app ids to their screenshot URLs.
    func respond(to term: String, apps: [(id: Int, screenshots: [URL])]) throws {
        let results = apps.map { app in
            ["trackId": app.id, "trackName": "App \(app.id)", "screenshotUrls": app.screenshots.map(\.absoluteString)] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: ["results": results])
        let request = try takeRequest(for: term)
        let response = HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        request.continuation.resume(returning: (data, response))
    }

    func fail(_ term: String, with error: any Error) throws {
        try takeRequest(for: term).continuation.resume(throwing: error)
    }

    private func takeRequest(for term: String) throws -> Request {
        let index = try XCTUnwrap(pending.firstIndex { $0.term == term }, "No pending search for \"\(term)\"")
        return pending.remove(at: index)
    }
}

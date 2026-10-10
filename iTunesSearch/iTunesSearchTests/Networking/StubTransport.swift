//
//  StubTransport.swift
//  iTunesSearchTests
//

import Foundation
@testable import iTunesSearch

enum StubTransport {
    static func client(status: Int = 200, body: String) -> APIClient {
        APIClient { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    static func client(throwing error: any Error) -> APIClient {
        APIClient { _ in throw error }
    }
}

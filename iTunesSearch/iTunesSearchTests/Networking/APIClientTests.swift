//
//  APIClientTests.swift
//  iTunesSearchTests
//

import XCTest
@testable import iTunesSearch

final class APIClientTests: XCTestCase {

    private struct Payload: Decodable, Equatable {
        let value: Int
    }

    private let url = URL(string: "https://example.com/resource")!

    func testSuccessfulResponseDecodesBody() async throws {
        let client = StubTransport.client(body: #"{"value": 42}"#)

        let payload = try await client.get(url, as: Payload.self)

        XCTAssertEqual(payload, Payload(value: 42))
    }

    func testNon2xxStatusMapsToHTTPStatusError() async {
        for status in [301, 403, 404, 500, 503] {
            let client = StubTransport.client(status: status, body: #"{"value": 1}"#)
            await assertAPIError(.httpStatus(status)) { try await client.get(self.url, as: Payload.self) }
        }
    }

    func testURLErrorMapsToTransportError() async {
        let client = StubTransport.client(throwing: URLError(.notConnectedToInternet))

        await assertAPIError(.transport(URLError(.notConnectedToInternet))) {
            try await client.get(self.url, as: Payload.self)
        }
    }

    func testInvalidJSONMapsToDecodingError() async {
        let client = StubTransport.client(body: "not json")

        do {
            _ = try await client.get(url, as: Payload.self)
            XCTFail("Expected decoding error")
        } catch let APIError.decoding(message) {
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPResponseMapsToInvalidResponse() async {
        let client = APIClient { request in
            (Data(), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }

        await assertAPIError(.invalidResponse) { try await client.get(self.url, as: Payload.self) }
    }

    func testCancelledURLErrorIsRethrownAsCancellationError() async {
        let client = StubTransport.client(throwing: URLError(.cancelled))

        do {
            _ = try await client.get(url, as: Payload.self)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func assertAPIError<T>(
        _ expected: APIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as APIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

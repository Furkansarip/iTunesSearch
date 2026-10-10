//
//  APIClient.swift
//  iTunesSearch
//

import Foundation

nonisolated struct APIClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.transport = { request in try await session.data(for: request) }
    }

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// Cancellation (`CancellationError` or `URLError.cancelled`) is rethrown as `CancellationError`
    /// so callers can ignore it without inspecting transport errors.
    @concurrent
    func get<T: Decodable & Sendable>(_ url: URL, as type: T.Type = T.self) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(URLRequest(url: url))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw APIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

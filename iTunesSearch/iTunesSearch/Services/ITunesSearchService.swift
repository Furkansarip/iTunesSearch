//
//  ITunesSearchService.swift
//  iTunesSearch
//

import Foundation

nonisolated struct ITunesSearchService: Sendable {
    static let resultLimit = 25
    static let media = "software"

    /// RFC 3986 unreserved characters. Everything else, including `+`, `&`, `=`, spaces and
    /// non-ASCII text, is percent-encoded; the server would otherwise decode a literal `+` as a space.
    private static let allowedQueryCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func search(term: String) async throws -> [AppResult] {
        guard let url = Self.makeURL(term: term) else { throw APIError.invalidURL }
        let response = try await client.get(url, as: ITunesSearchResponseDTO.self)
        return response.results.map { $0.toDomain() }
    }

    static func makeURL(term: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"

        let items = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: media),
            URLQueryItem(name: "limit", value: String(resultLimit)),
        ]
        components.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: allowedQueryCharacters))
        }
        return components.url
    }
}

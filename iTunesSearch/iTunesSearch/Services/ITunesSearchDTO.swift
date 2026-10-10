//
//  ITunesSearchDTO.swift
//  iTunesSearch
//

import Foundation

nonisolated struct ITunesSearchResponseDTO: Decodable, Sendable {
    let results: [ITunesAppDTO]

    private enum CodingKeys: String, CodingKey {
        case results
    }

    /// A malformed entry is skipped; a missing or non-array `results` still fails decoding.
    private struct FailableApp: Decodable {
        let app: ITunesAppDTO?

        init(from decoder: Decoder) throws {
            app = try? ITunesAppDTO(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decode([FailableApp].self, forKey: .results).compactMap(\.app)
    }
}

nonisolated struct ITunesAppDTO: Decodable, Sendable {
    let trackId: Int
    let trackName: String
    let artistName: String?
    let screenshotUrls: [String]

    private enum CodingKeys: String, CodingKey {
        case trackId, trackName, artistName, screenshotUrls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackId = try container.decode(Int.self, forKey: .trackId)
        trackName = try container.decode(String.self, forKey: .trackName)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        let urls = try container.decodeIfPresent([String?].self, forKey: .screenshotUrls) ?? []
        screenshotUrls = urls.compactMap { $0 }
    }
}

extension ITunesAppDTO {
    nonisolated func toDomain() -> AppResult {
        AppResult(
            id: trackId,
            name: trackName,
            developer: artistName ?? "",
            screenshotURLs: screenshotUrls.compactMap(Self.screenshotURL(from:))
        )
    }

    /// Only absolute HTTPS URLs with a host are supported; App Transport Security blocks plain HTTP.
    nonisolated static func screenshotURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
}

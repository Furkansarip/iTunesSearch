//
//  APIError.swift
//  iTunesSearch
//

import Foundation

nonisolated enum APIError: Error, Equatable {
    case invalidURL
    case transport(URLError)
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)
}

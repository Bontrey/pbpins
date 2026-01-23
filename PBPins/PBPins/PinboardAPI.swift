//
//  PinboardAPI.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import Foundation

struct PostsResponse: Codable {
    let date: String
    let user: String
    let posts: [APIBookmark]
}

struct APIBookmark: Codable {
    let href: String
    let description: String
    let extended: String
    let meta: String
    let hash: String
    let time: String
    let shared: String
    let toread: String
    let tags: String
}

enum PinboardError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

class PinboardAPI {
    private let baseURL = "https://api.pinboard.in/v1"

    let apiToken: String

    init(apiToken: String) {
        self.apiToken = apiToken
    }

    func fetchRecentBookmarks(count: Int = 100) async throws -> [APIBookmark] {
        guard var urlComponents = URLComponents(string: "\(baseURL)/posts/recent") else {
            throw PinboardError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "auth_token", value: apiToken),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "count", value: String(min(count, 100)))
        ]

        guard let url = urlComponents.url else {
            throw PinboardError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PinboardError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw PinboardError.httpError(httpResponse.statusCode)
        }

        do {
            let postsResponse = try JSONDecoder().decode(PostsResponse.self, from: data)
            return postsResponse.posts
        } catch {
            throw PinboardError.decodingError(error)
        }
    }
}

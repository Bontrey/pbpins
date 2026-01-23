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

struct APIBookmark: Codable, Identifiable {
    let href: String
    let description: String
    let extended: String
    let meta: String
    let hash: String
    let time: String
    let shared: String
    var toread: String
    let tags: String

    var id: String { hash }
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

    func updateBookmark(
        url: String,
        title: String,
        description: String = "",
        tags: [String] = [],
        isPrivate: Bool = false,
        isUnread: Bool = false
    ) async throws {
        guard var urlComponents = URLComponents(string: "\(baseURL)/posts/add") else {
            throw PinboardError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "auth_token", value: apiToken),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "description", value: title),
            URLQueryItem(name: "extended", value: description),
            URLQueryItem(name: "tags", value: tags.joined(separator: " ")),
            URLQueryItem(name: "shared", value: isPrivate ? "no" : "yes"),
            URLQueryItem(name: "toread", value: isUnread ? "yes" : "no"),
            URLQueryItem(name: "replace", value: "yes")
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

        // Check for API error in response
        if let responseString = String(data: data, encoding: .utf8),
           responseString.contains("\"result_code\":\"done\"") == false {
            throw PinboardError.invalidResponse
        }
    }

    func deleteBookmark(url: String) async throws {
        guard var urlComponents = URLComponents(string: "\(baseURL)/posts/delete") else {
            throw PinboardError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "auth_token", value: apiToken),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: url)
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

        // Check for API error in response
        if let responseString = String(data: data, encoding: .utf8),
           responseString.contains("\"result_code\":\"done\"") == false {
            throw PinboardError.invalidResponse
        }
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

    func fetchAllBookmarks(start: Int = 0, results: Int = 100, tag: String? = nil) async throws -> [APIBookmark] {
        guard var urlComponents = URLComponents(string: "\(baseURL)/posts/all") else {
            throw PinboardError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "auth_token", value: apiToken),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "start", value: String(start)),
            URLQueryItem(name: "results", value: String(results))
        ]

        if let tag = tag {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }

        urlComponents.queryItems = queryItems

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
            // posts/all returns an array directly, not wrapped in PostsResponse
            let bookmarks = try JSONDecoder().decode([APIBookmark].self, from: data)
            return bookmarks
        } catch {
            throw PinboardError.decodingError(error)
        }
    }

    func fetchAllTags() async throws -> [(tag: String, count: Int)] {
        guard var urlComponents = URLComponents(string: "\(baseURL)/tags/get") else {
            throw PinboardError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "auth_token", value: apiToken),
            URLQueryItem(name: "format", value: "json")
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
            // Response is a dictionary: {"tagname": count, ...} where count is an integer
            let tagsDict = try JSONDecoder().decode([String: Int].self, from: data)
            return tagsDict
                .map { (tag: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        } catch {
            throw PinboardError.decodingError(error)
        }
    }
}

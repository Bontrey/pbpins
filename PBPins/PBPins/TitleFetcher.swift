//
//  TitleFetcher.swift
//  PBPins
//
//  Created by Long Wei on 23.01.2026.
//

import Foundation

enum TitleFetcher {
    static func fetchTitle(from url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return extractTitleFromHTML(html)
        }

        return nil
    }

    private static func extractTitleFromHTML(_ html: String) -> String? {
        let patterns = [
            "<title[^>]*>([^<]+)</title>",
            "<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let title = String(html[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&ndash;", with: "–")
                    .replacingOccurrences(of: "&#8211;", with: "–")
                    .replacingOccurrences(of: "&mdash;", with: "—")
                    .replacingOccurrences(of: "&#8212;", with: "—")

                if !title.isEmpty {
                    return title
                }
            }
        }

        return nil
    }
}

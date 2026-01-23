//
//  ShareViewController.swift
//  PBPinsShareExtension
//
//  Created by Long Wei on 22.01.2026.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareExtensionView(
            extensionContext: extensionContext
        )

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
    }
}

struct ShareExtensionView: View {
    let extensionContext: NSExtensionContext?

    @State private var url: String = ""
    @State private var title: String = ""
    @State private var tags: String = ""
    @State private var isUnread: Bool = true
    @State private var isPrivate: Bool = false
    @State private var isFetchingTitle: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    private let apiTokenKey = "pinboard_api_token"

    private var apiToken: String {
        // Try App Group first, then fall back to standard UserDefaults
        if let groupDefaults = UserDefaults(suiteName: "group.ch.longwei.PBPins"),
           let token = groupDefaults.string(forKey: apiTokenKey),
           !token.isEmpty {
            return token
        }
        return UserDefaults.standard.string(forKey: apiTokenKey) ?? ""
    }

    private var isLoggedIn: Bool {
        !apiToken.isEmpty && apiToken.contains(":")
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isLoggedIn {
                    notLoggedInView
                } else {
                    formView
                }
            }
            .navigationTitle("Save Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                    }
                }

                if isLoggedIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save()
                        }
                        .disabled(url.isEmpty || title.isEmpty || isSaving)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
        .task {
            await extractURL()
        }
    }

    private var notLoggedInView: some View {
        ContentUnavailableView(
            "Not Logged In",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Please open PBPins and log in with your Pinboard API token first.")
        )
    }

    private var formView: some View {
        Form {
            Section("URL") {
                if isFetchingTitle {
                    ProgressView()
                } else {
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if !isFetchingTitle && urlHasTrackingParameters {
                    Button("Remove Tracking Parameters") {
                        url = removeTrackingParameters(from: url)
                    }
                }
            }

            Section("Title") {
                TextField("Title", text: $title)
            }

            Section {
                TextField("Tags", text: $tags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Separate multiple tags with spaces")
            }

            Section {
                Toggle("Mark as Unread", isOn: $isUnread)
                Toggle("Private", isOn: $isPrivate)
            }

            if isSaving {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Saving...")
                        Spacer()
                    }
                }
            }
        }
    }

    private func extractURL() async {
        guard let extensionContext = extensionContext,
              let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
            return
        }

        for item in inputItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try to get URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                        if let sharedURL = item as? URL {
                            await MainActor.run {
                                self.url = sharedURL.absoluteString
                                self.title = sharedURL.host ?? sharedURL.absoluteString
                            }
                            await fetchTitle(from: sharedURL)
                            return
                        }
                    } catch {
                        print("Error loading URL: \(error)")
                    }
                }

                // Try to get plain text (might be a URL string)
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    do {
                        let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
                        if let text = item as? String,
                           let sharedURL = URL(string: text),
                           sharedURL.scheme?.hasPrefix("http") == true {
                            await MainActor.run {
                                self.url = sharedURL.absoluteString
                                self.title = sharedURL.host ?? sharedURL.absoluteString
                            }
                            await fetchTitle(from: sharedURL)
                            return
                        }
                    } catch {
                        print("Error loading text: \(error)")
                    }
                }
            }
        }
    }

    private func fetchTitle(from url: URL) async {
        await MainActor.run {
            isFetchingTitle = true
        }

        defer {
            Task { @MainActor in
                isFetchingTitle = false
            }
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
               let extractedTitle = extractTitleFromHTML(html) {
                await MainActor.run {
                    self.title = extractedTitle
                }
            }
        } catch {
            print("Error fetching title: \(error)")
            // Keep the default title (host or URL)
        }
    }

    private func extractTitleFromHTML(_ html: String) -> String? {
        // Try to find <title> tag
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

    private static let trackingParameters: Set<String> = [
        // Google Analytics / Ads
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_source_platform", "utm_creative_format", "utm_marketing_tactic",
        "gclid", "gclsrc", "dclid", "gad_source",
        // Facebook
        "fbclid", "fb_action_ids", "fb_action_types", "fb_source", "fb_ref",
        // Twitter/X
        "twclid",
        // Microsoft/Bing
        "msclkid",
        // TikTok
        "ttclid",
        // Mailchimp
        "mc_cid", "mc_eid",
        // HubSpot
        "hsa_acc", "hsa_cam", "hsa_grp", "hsa_ad", "hsa_src", "hsa_tgt",
        "hsa_kw", "hsa_mt", "hsa_net", "hsa_ver",
        // Marketo
        "mkt_tok",
        // Adobe
        "s_kwcid", "ef_id",
        // Other common trackers
        "ref", "ref_src", "ref_url", "source", "campaign",
        "igshid", // Instagram
        "si", // Spotify
        "at_medium", "at_campaign", // AT Internet
        "oly_enc_id", "oly_anon_id", // Omeda
        "vero_id", "vero_conv",
        "wickedid",
        "yclid", // Yandex
        "_hsenc", "_hsmi", // HubSpot
        "trk", "trkInfo", // LinkedIn
        "cvid", "oicd", // Microsoft
        "ncid", "sr_share", // Various news sites
    ]

    private var urlHasTrackingParameters: Bool {
        guard let components = URLComponents(string: url),
              let queryItems = components.queryItems else {
            return false
        }
        return queryItems.contains { item in
            Self.trackingParameters.contains(item.name.lowercased())
        }
    }

    private func removeTrackingParameters(from urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        if let queryItems = components.queryItems {
            let filteredItems = queryItems.filter { item in
                !Self.trackingParameters.contains(item.name.lowercased())
            }
            components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        }

        return components.string ?? urlString
    }

    private func save() {
        guard !url.isEmpty, !title.isEmpty else { return }

        isSaving = true

        Task {
            do {
                let api = SharePinboardAPI(apiToken: apiToken)
                let tagArray = tags.split(separator: " ").map(String.init)

                try await api.addBookmark(
                    url: url,
                    title: title,
                    tags: tagArray,
                    isPrivate: isPrivate,
                    isUnread: isUnread
                )

                // Signal to main app that a bookmark was saved
                if let groupDefaults = UserDefaults(suiteName: "group.ch.longwei.PBPins") {
                    groupDefaults.set(true, forKey: "needs_refresh")
                }

                await MainActor.run {
                    extensionContext?.completeRequest(returningItems: nil)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "PBPinsShareExtension", code: 0))
    }
}

// Minimal Pinboard API client for the share extension
class SharePinboardAPI {
    private let baseURL = "https://api.pinboard.in/v1"
    private let apiToken: String

    init(apiToken: String) {
        self.apiToken = apiToken
    }

    func addBookmark(
        url: String,
        title: String,
        tags: [String] = [],
        isPrivate: Bool = false,
        isUnread: Bool = false
    ) async throws {
        guard var urlComponents = URLComponents(string: "\(baseURL)/posts/add") else {
            throw ShareError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "auth_token", value: apiToken),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "description", value: title),
            URLQueryItem(name: "tags", value: tags.joined(separator: " ")),
            URLQueryItem(name: "shared", value: isPrivate ? "no" : "yes"),
            URLQueryItem(name: "toread", value: isUnread ? "yes" : "no"),
            URLQueryItem(name: "replace", value: "yes")
        ]

        guard let requestURL = urlComponents.url else {
            throw ShareError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: requestURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ShareError.httpError(httpResponse.statusCode)
        }

        if let responseString = String(data: data, encoding: .utf8),
           !responseString.contains("\"result_code\":\"done\"") {
            throw ShareError.invalidResponse
        }
    }
}

enum ShareError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Failed to save bookmark"
        case .httpError(let code):
            return "Server error: \(code)"
        }
    }
}

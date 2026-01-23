//
//  AuthManager.swift
//  PBPins
//
//  Created by Long Wei on 22.01.2026.
//

import Foundation
import SwiftUI

@Observable
class AuthManager {
    private let apiTokenKey = "pinboard_api_token"
    private let appGroupID = "group.ch.longwei.PBPins"

    var apiToken: String {
        didSet {
            // Store in both standard and App Group UserDefaults for share extension access
            UserDefaults.standard.set(apiToken, forKey: apiTokenKey)
            UserDefaults(suiteName: appGroupID)?.set(apiToken, forKey: apiTokenKey)
        }
    }

    var username: String {
        guard let colonIndex = apiToken.firstIndex(of: ":") else { return "" }
        return String(apiToken[..<colonIndex])
    }

    var isLoggedIn: Bool {
        !apiToken.isEmpty && apiToken.contains(":")
    }

    init() {
        // Try App Group first, then fall back to standard UserDefaults
        if let groupDefaults = UserDefaults(suiteName: appGroupID),
           let token = groupDefaults.string(forKey: apiTokenKey),
           !token.isEmpty {
            self.apiToken = token
        } else {
            self.apiToken = UserDefaults.standard.string(forKey: apiTokenKey) ?? ""
        }
    }

    func login(apiToken: String) {
        self.apiToken = apiToken
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: apiTokenKey)
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: apiTokenKey)
        self.apiToken = ""
    }

    func createAPI() -> PinboardAPI? {
        guard isLoggedIn else { return nil }
        return PinboardAPI(apiToken: apiToken)
    }
}

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

    var apiToken: String {
        didSet {
            UserDefaults.standard.set(apiToken, forKey: apiTokenKey)
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
        self.apiToken = UserDefaults.standard.string(forKey: apiTokenKey) ?? ""
    }

    func login(apiToken: String) {
        self.apiToken = apiToken
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: apiTokenKey)
        self.apiToken = ""
    }

    func createAPI() -> PinboardAPI? {
        guard isLoggedIn else { return nil }
        return PinboardAPI(apiToken: apiToken)
    }
}

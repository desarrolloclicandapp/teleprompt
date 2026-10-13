import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit

@MainActor
final class GoogleOAuth: NSObject, ObservableObject {
    @Published private(set) var isConnected = false
    @Published var errorMessage: String?
    private var session: ASWebAuthenticationSession?
    private var verifier = ""
    private var authorizationState = ""

    override init() {
        super.init()
        isConnected = KeychainStore.get("teleprompt.drive-access-token") != nil
    }

    private var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
    }

    private var callbackScheme: String {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return "" }
        return "com.googleusercontent.apps.\(clientID.dropLast(suffix.count))"
    }

    private var redirectURI: String {
        "\(callbackScheme):/oauthredirect"
    }

    func connect() {
        guard session == nil else { return }
        errorMessage = nil
        guard !clientID.isEmpty, !clientID.contains("REPLACE"), !callbackScheme.isEmpty else {
            errorMessage = String(localized: "oauth.invalid_client_id")
            return
        }
        verifier = Self.randomString(length: 64)
        authorizationState = Self.randomString(length: 32)
        let challenge = Self.challenge(for: verifier)
        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            errorMessage = String(localized: "oauth.could_not_start")
            return
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: authorizationState)
        ]
        guard let authorizationURL = components.url else {
            errorMessage = String(localized: "oauth.could_not_start")
            return
        }
        session = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self else { return }
            let expectedState = self.authorizationState
            defer {
                self.authorizationState = ""
                self.session = nil
            }
            guard let callbackURL else {
                self.errorMessage = error.map {
                    String(format: String(localized: "oauth.completion_error_format"), $0.localizedDescription)
                } ?? String(localized: "oauth.no_response")
                return
            }
            let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
                self.errorMessage = String(localized: "oauth.invalid_state")
                return
            }
            if let authorizationError = queryItems.first(where: { $0.name == "error" })?.value {
                let description = queryItems.first(where: { $0.name == "error_description" })?.value
                if authorizationError == "access_denied" {
                    self.errorMessage = String(localized: "oauth.access_denied")
                } else {
                    self.errorMessage = description.map {
                        String(format: String(localized: "oauth.authorization_error_format"), $0)
                    } ?? String(format: String(localized: "oauth.authorization_rejected_format"), authorizationError)
                }
                return
            }
            guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
                self.errorMessage = String(localized: "oauth.no_code")
                return
            }
            Task { await self.exchange(code: code) }
        }
        session?.presentationContextProvider = self
        session?.prefersEphemeralWebBrowserSession = false
        guard session?.start() == true else {
            session = nil
            authorizationState = ""
            errorMessage = String(localized: "oauth.could_not_start")
            return
        }
    }

    func disconnect() {
        KeychainStore.remove("teleprompt.drive-access-token")
        KeychainStore.remove("teleprompt.drive-refresh-token")
        isConnected = false
        errorMessage = nil
    }

    private func exchange(code: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = URLFormEncoder.encode([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw DriveError.http((response as? HTTPURLResponse)?.statusCode ?? -1) }
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            KeychainStore.set(token.accessToken, key: "teleprompt.drive-access-token")
            if let refreshToken = token.refreshToken { KeychainStore.set(refreshToken, key: "teleprompt.drive-refresh-token") }
            isConnected = true
        } catch { errorMessage = error.localizedDescription }
    }

    private static func randomString(length: Int) -> String {
        String((0..<length).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleOAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

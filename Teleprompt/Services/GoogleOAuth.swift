import AuthenticationServices
import Combine
import CryptoKit
import Foundation

@MainActor
final class GoogleOAuth: NSObject, ObservableObject {
    @Published private(set) var isConnected = false
    @Published var errorMessage: String?
    private var session: ASWebAuthenticationSession?
    private var verifier = ""

    private var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
    }

    private var redirectURI: String {
        "com.googleusercontent.apps.907761302167-ql6fmvbli2gcnlgobo02gb3t6raca8bq:/oauthredirect"
    }

    func connect() {
        guard !clientID.isEmpty, !clientID.contains("REPLACE") else {
            errorMessage = "Falta configurar GOOGLE_CLIENT_ID en Codemagic y en Info.plist."
            return
        }
        verifier = Self.randomString(length: 64)
        let challenge = Self.challenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "com.googleusercontent.apps.907761302167-ql6fmvbli2gcnlgobo02gb3t6raca8bq") { [weak self] callbackURL, error in
            guard let self else { return }
            if let error { self.errorMessage = error.localizedDescription; return }
            guard let callbackURL, let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                self.errorMessage = "Google no devolvió un código de autorización."
                return
            }
            Task { await self.exchange(code: code) }
        }
        session?.presentationContextProvider = self
        session?.prefersEphemeralWebBrowserSession = false
        session?.start()
    }

    func disconnect() {
        KeychainStore.remove("teleprompt.drive-access-token")
        KeychainStore.remove("teleprompt.drive-refresh-token")
        isConnected = false
    }

    private func exchange(code: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&").data(using: .utf8)
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
        MainActor.assumeIsolated { ASPresentationAnchor() }
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

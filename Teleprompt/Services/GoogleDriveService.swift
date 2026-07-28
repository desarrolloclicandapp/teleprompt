import Foundation

struct DriveFile: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let md5Checksum: String?

    var isScript: Bool {
        let lower = name.lowercased()
        return (lower.hasSuffix(".txt") || lower.hasSuffix(".md")) && mimeType != "application/vnd.google-apps.folder"
    }
}

actor GoogleDriveService {
    static let shared = GoogleDriveService()
    private let baseURL = URL(string: "https://www.googleapis.com/drive/v3")!

    func listScripts(in folderID: String, accessToken: String, pageToken: String? = nil) async throws -> [DriveFile] {
        var components = URLComponents(url: baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
        let query = "'\(folderID)' in parents and trashed = false and (mimeType = 'text/plain' or mimeType = 'text/markdown' or mimeType = 'application/pdf' or mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,md5Checksum),nextPageToken"),
            URLQueryItem(name: "orderBy", value: "name")
        ]
        if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        let response: DriveFilesResponse = try await request(components.url!, accessToken: accessToken)
        return response.files
    }

    func download(fileID: String, accessToken: String) async throws -> String {
        let data = try await downloadData(fileID: fileID, accessToken: accessToken)
        guard let text = String(data: data, encoding: .utf8) else { throw DriveError.invalidText }
        return text
    }

    func downloadData(fileID: String, accessToken: String) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("files/\(fileID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(components.url!, accessToken: accessToken))
        try validate(response)
        return data
    }

    func upload(text: String, fileID: String, accessToken: String) async throws {
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media")!
        var request = authorizedRequest(url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = text.data(using: .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    func refreshAccessToken(refreshToken: String, clientID: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = ["client_id": clientID, "refresh_token": refreshToken, "grant_type": "refresh_token"]
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let token = try JSONDecoder().decode(RefreshResponse.self, from: data)
        return token.accessToken
    }

    private func request<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(url, accessToken: accessToken))
        try validate(response)
        return try driveJSONDecoder.decode(T.self, from: data)
    }

    private func authorizedRequest(_ url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DriveError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}

private struct RefreshResponse: Decodable { let accessToken: String; enum CodingKeys: String, CodingKey { case accessToken = "access_token" } }

private struct DriveFilesResponse: Decodable {
    let files: [DriveFile]
}

enum DriveError: LocalizedError {
    case http(Int)
    case invalidText
    var errorDescription: String? {
        switch self {
        case .http(401): return "La sesión de Google Drive expiró. Vuelve a conectar la cuenta."
        case .http(403): return "Google Drive denegó el acceso (403). Verifica que tu cuenta esté en OAuth consent screen > Test users y vuelve a conectar."
        case .http(let code): return "Google Drive respondió con el código \(code)."
        case .invalidText: return "El archivo no contiene texto UTF-8 válido."
        }
    }
}

private let driveJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

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
        let query = "'\(folderID)' in parents and trashed = false and (mimeType = 'text/plain' or mimeType = 'text/markdown')"
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
        var components = URLComponents(url: baseURL.appendingPathComponent("files/\(fileID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(components.url!, accessToken: accessToken))
        try validate(response)
        guard let text = String(data: data, encoding: .utf8) else { throw DriveError.invalidText }
        return text
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

    private func request<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(url, accessToken: accessToken))
        try validate(response)
        return try JSONDecoder.drive.decode(T.self, from: data)
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

private struct DriveFilesResponse: Decodable {
    let files: [DriveFile]
}

enum DriveError: LocalizedError {
    case http(Int)
    case invalidText
    var errorDescription: String? {
        switch self {
        case .http(let code): return "Google Drive respondió con el código \(code)."
        case .invalidText: return "El archivo no contiene texto UTF-8 válido."
        }
    }
}

private extension JSONDecoder {
    static let drive: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

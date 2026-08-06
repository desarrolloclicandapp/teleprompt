import Foundation

struct DriveFile: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let md5Checksum: String?
    let folderPath: String?

    init(
        id: String,
        name: String,
        mimeType: String,
        modifiedTime: Date? = nil,
        md5Checksum: String? = nil,
        folderPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.md5Checksum = md5Checksum
        self.folderPath = folderPath
    }

    var isScript: Bool {
        let lower = name.lowercased()
        return (lower.hasSuffix(".txt") || lower.hasSuffix(".md")) && mimeType != "application/vnd.google-apps.folder"
    }
}

struct DriveFolder: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let parentID: String?
    let parentName: String?

    init(id: String, name: String, parentID: String? = nil, parentName: String? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.parentName = parentName
    }
}

actor GoogleDriveService {
    static let shared = GoogleDriveService()
    private let baseURL = URL(string: "https://www.googleapis.com/drive/v3")!

    func listScripts(in folderID: String, accessToken: String, pageToken: String? = nil) async throws -> [DriveFile] {
        let query = "'\(folderID)' in parents and trashed = false and (mimeType = 'text/plain' or mimeType = 'text/markdown' or mimeType = 'application/pdf' or mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')"
        var files: [DriveFile] = []
        var currentPageToken = pageToken

        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,md5Checksum),nextPageToken"),
                URLQueryItem(name: "orderBy", value: "name"),
                URLQueryItem(name: "pageSize", value: "1000")
            ]
            if let currentPageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: currentPageToken))
            }
            let response: DriveFilesResponse = try await request(components.url!, accessToken: accessToken)
            files.append(contentsOf: response.files)
            currentPageToken = response.nextPageToken
        } while currentPageToken != nil

        return files
    }

    func listScriptsRecursively(
        in folderID: String,
        accessToken: String,
        path: String = ""
    ) async throws -> [DriveFile] {
        let directFiles = try await listScripts(in: folderID, accessToken: accessToken)
            .map {
                DriveFile(
                    id: $0.id,
                    name: $0.name,
                    mimeType: $0.mimeType,
                    modifiedTime: $0.modifiedTime,
                    md5Checksum: $0.md5Checksum,
                    folderPath: path.isEmpty ? nil : path
                )
            }

        let childFolders = try await listFolders(in: folderID, accessToken: accessToken)
        var files = directFiles
        for folder in childFolders {
            let childPath = path.isEmpty ? folder.name : "\(path)/\(folder.name)"
            files += try await listScriptsRecursively(
                in: folder.id,
                accessToken: accessToken,
                path: childPath
            )
        }
        return files.sorted { lhs, rhs in
            let leftPath = lhs.folderPath ?? ""
            let rightPath = rhs.folderPath ?? ""
            let pathOrder = leftPath.localizedCaseInsensitiveCompare(rightPath)
            if pathOrder != .orderedSame {
                return pathOrder == .orderedAscending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func listFolders(in parentID: String, accessToken: String) async throws -> [DriveFolder] {
        let query = "'\(parentID)' in parents and trashed = false and mimeType = 'application/vnd.google-apps.folder'"
        var folders: [DriveFolder] = []
        var currentPageToken: String?

        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "fields", value: "files(id,name),nextPageToken"),
                URLQueryItem(name: "orderBy", value: "name_natural"),
                URLQueryItem(name: "pageSize", value: "1000")
            ]
            if let currentPageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: currentPageToken))
            }
            let response: DriveFoldersResponse = try await request(components.url!, accessToken: accessToken)
            folders.append(contentsOf: response.files)
            currentPageToken = response.nextPageToken
        } while currentPageToken != nil

        return folders
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

    // Read-only integration by design. Upload API is intentionally disabled.
    func upload(text: String, fileID: String, accessToken: String) async throws {
        _ = text
        _ = fileID
        _ = accessToken
        throw DriveError.uploadDisabled
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
    let nextPageToken: String?
}

private struct DriveFoldersResponse: Decodable {
    let files: [DriveFolder]
    let nextPageToken: String?
}

enum DriveError: LocalizedError {
    case notConnected
    case http(Int)
    case invalidText
    case uploadDisabled
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Conecta Google Drive para elegir una carpeta."
        case .http(401): return "La sesión de Google Drive expiró. Vuelve a conectar la cuenta."
        case .http(403): return "Google Drive denegó el acceso (403). Verifica que tu cuenta esté en OAuth consent screen > Test users y vuelve a conectar."
        case .http(404): return "No se encontró la carpeta de Google Drive. Elige una carpeta nuevamente desde el selector."
        case .http(let code): return "Google Drive respondió con el código \(code)."
        case .invalidText: return "El archivo no contiene texto UTF-8 válido."
        case .uploadDisabled: return "Google Drive esta en modo solo lectura. Esta app solo descarga scripts y no sube ni modifica archivos."
        }
    }
}

private let driveJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()


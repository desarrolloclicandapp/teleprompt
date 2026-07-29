import Foundation
import Combine

@MainActor
final class DriveSyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published var message: String?

    private let folderKey = "teleprompt.drive-folder-id"
    private let folderNameKey = "teleprompt.drive-folder-name"
    private let folderParentKey = "teleprompt.drive-folder-parent-id"
    private let folderParentNameKey = "teleprompt.drive-folder-parent-name"
    private let tokenKey = "teleprompt.drive-access-token"
    private let refreshKey = "teleprompt.drive-refresh-token"

    var folderID: String? {
        get { UserDefaults.standard.string(forKey: folderKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderKey) }
    }

    var folderName: String? {
        get { UserDefaults.standard.string(forKey: folderNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderNameKey) }
    }

    var folderParentID: String? {
        get { UserDefaults.standard.string(forKey: folderParentKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderParentKey) }
    }

    var folderParentName: String? {
        get { UserDefaults.standard.string(forKey: folderParentNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderParentNameKey) }
    }

    func selectFolder(_ folder: DriveFolder) {
        folderID = folder.id
        folderName = folder.name
        folderParentID = folder.parentID
        folderParentName = folder.parentName
        message = "Carpeta seleccionada: \(folder.name)."
    }

    func clearSelectedFolder() {
        folderID = nil
        folderName = nil
        folderParentID = nil
        folderParentName = nil
    }

    func listFolders(in parentID: String = "root") async throws -> [DriveFolder] {
        guard let token = KeychainStore.get(tokenKey) else {
            throw DriveError.notConnected
        }

        do {
            return try await GoogleDriveService.shared.listFolders(in: parentID, accessToken: token)
        } catch {
            guard case DriveError.http(401) = error,
                  let refresh = KeychainStore.get(refreshKey),
                  let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String else {
                throw error
            }

            let renewed = try await GoogleDriveService.shared.refreshAccessToken(refreshToken: refresh, clientID: clientID)
            KeychainStore.set(renewed, key: tokenKey)
            return try await GoogleDriveService.shared.listFolders(in: parentID, accessToken: renewed)
        }
    }

    func sync(library: ScriptLibrary) async {
        guard let folderID, folderName != nil, let token = KeychainStore.get(tokenKey) else {
            message = "Conecta Google Drive y elige una carpeta para sincronizar."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var activeToken = token
            let files: [DriveFile]
            do {
                files = try await GoogleDriveService.shared.listScriptsRecursively(in: folderID, accessToken: activeToken)
            } catch {
                guard case DriveError.http(401) = error,
                      let refresh = KeychainStore.get(refreshKey),
                      let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String else {
                    throw error
                }
                let renewed = try await GoogleDriveService.shared.refreshAccessToken(refreshToken: refresh, clientID: clientID)
                KeychainStore.set(renewed, key: tokenKey)
                activeToken = renewed
                files = try await GoogleDriveService.shared.listScriptsRecursively(in: folderID, accessToken: activeToken)
            }
            for file in files {
                let data = try await GoogleDriveService.shared.downloadData(fileID: file.id, accessToken: activeToken)
                let document = try DocumentImporter.read(data: data, fileExtension: file.name.split(separator: ".").last.map(String.init) ?? "txt", title: file.name)
                let sourcePath = file.folderPath.map { "Google Drive/\($0)" } ?? "Google Drive"
                _ = library.importDocument(
                    title: document.title,
                    text: document.text,
                    sourcePath: sourcePath,
                    sourceID: file.id
                )
            }
            lastSync = .now
            message = "Google Drive sincronizado."
        } catch {
            message = error.localizedDescription
        }
    }
}

import Foundation

@MainActor
final class DriveSyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published var message: String?

    private let folderKey = "teleprompt.drive-folder-id"
    private let tokenKey = "teleprompt.drive-access-token"
    private let refreshKey = "teleprompt.drive-refresh-token"

    var folderID: String? {
        get { UserDefaults.standard.string(forKey: folderKey) }
        set { UserDefaults.standard.set(newValue, forKey: folderKey) }
    }

    func sync(library: ScriptLibrary) async {
        guard let folderID, let token = KeychainStore.get(tokenKey) else {
            message = "Conecta Google Drive y elige una carpeta para sincronizar."
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let files: [DriveFile]
            do {
                files = try await GoogleDriveService.shared.listScripts(in: folderID, accessToken: token)
            } catch DriveError.http(401) {
                guard let refresh = KeychainStore.get(refreshKey), let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String else { throw DriveError.http(401) }
                let renewed = try await GoogleDriveService.shared.refreshAccessToken(refreshToken: refresh, clientID: clientID)
                KeychainStore.set(renewed, key: tokenKey)
                files = try await GoogleDriveService.shared.listScripts(in: folderID, accessToken: renewed)
            }
            for file in files {
                let data = try await GoogleDriveService.shared.downloadData(fileID: file.id, accessToken: token)
                let document = try DocumentImporter.read(data: data, fileExtension: file.name.split(separator: ".").last.map(String.init) ?? "txt", title: file.name)
                let existing = library.scripts.first { $0.title == document.title }
                if var existing {
                    existing.text = document.text
                    library.upsert(existing)
                } else {
                    _ = library.add(title: document.title, text: document.text)
                }
            }
            lastSync = .now
            message = "Google Drive sincronizado."
        } catch {
            message = error.localizedDescription
        }
    }
}

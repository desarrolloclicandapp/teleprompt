import Foundation

@MainActor
final class DriveSyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSync: Date?
    @Published var message: String?

    private let folderKey = "teleprompt.drive-folder-id"
    private let tokenKey = "teleprompt.drive-access-token"

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
            let files = try await GoogleDriveService.shared.listScripts(in: folderID, accessToken: token)
            for file in files {
                let content = try await GoogleDriveService.shared.download(fileID: file.id, accessToken: token)
                let existing = library.scripts.first { $0.title == file.name.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: ".txt", with: "") }
                if var existing {
                    existing.text = content
                    library.upsert(existing)
                } else {
                    _ = library.add(title: file.name, text: content)
                }
            }
            lastSync = .now
            message = "Google Drive sincronizado."
        } catch {
            message = error.localizedDescription
        }
    }
}


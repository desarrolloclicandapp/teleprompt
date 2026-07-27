import Foundation
import UniformTypeIdentifiers

@MainActor
final class ExternalFolderAccess: ObservableObject {
    @Published private(set) var folderName: String?
    private let bookmarkKey = "teleprompt.external-folder-bookmark"

    func rememberFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        folderName = url.lastPathComponent
    }

    func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { rememberFolder(url) }
        folderName = url.lastPathComponent
        return url
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
    }
}


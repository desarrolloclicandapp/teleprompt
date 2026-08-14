import Foundation
import Combine

@MainActor
final class ExternalFolderAccess: ObservableObject {
    @Published private(set) var folderName: String?
    @Published private(set) var isSyncing = false
    @Published var message: String?
    private let bookmarkKey = "teleprompt.external-folder-bookmark"

    init() {
        _ = resolveFolder()
    }

    func rememberFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        // iOS already grants a security-scoped URL from the document picker.
        // Plain bookmark data is the portable option available to the iOS SDK.
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        folderName = url.lastPathComponent
    }

    func resolveFolder() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { rememberFolder(url) }
        folderName = url.lastPathComponent
        return url
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        folderName = nil
        message = nil
    }

    func sync(library: ScriptLibrary) async {
        guard !isSyncing else { return }
        guard let folderURL = resolveFolder() else {
            message = String(localized: "local.choose_folder_message")
            return
        }
        guard folderURL.startAccessingSecurityScopedResource() else {
            message = String(localized: "local.folder_access_error")
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        isSyncing = true
        defer { isSyncing = false }

        let allowedExtensions: Set<String> = ["txt", "md", "pdf", "docx"]
        var imported = 0
        var skipped = 0
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  allowedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            do {
                let document = try DocumentImporter.read(url: url)
                let relativeDirectory = relativeDirectory(for: url, folderURL: folderURL)
                let sourcePath = relativeDirectory.isEmpty
                    ? "Carpeta local"
                    : "Carpeta local/\(relativeDirectory)"
                _ = library.importDocument(
                    title: document.title,
                    text: document.text,
                    sourcePath: sourcePath,
                    sourceID: "local-folder:\(url.standardizedFileURL.path)"
                )
                imported += 1
            } catch {
                skipped += 1
            }
        }

        let importedSummary = imported == 1
            ? String(localized: "local.one_file_imported")
            : String(format: String(localized: "local.multiple_files_imported"), imported)
        if skipped == 0 {
            message = String(format: String(localized: "local.sync_success_format"), importedSummary)
        } else {
            let skippedSummary = skipped == 1
                ? String(localized: "local.one_file_skipped")
                : String(format: String(localized: "local.multiple_files_skipped"), skipped)
            message = String(format: String(localized: "local.sync_partial_format"), importedSummary, skippedSummary)
        }
    }

    private func relativeDirectory(for fileURL: URL, folderURL: URL) -> String {
        let folderPath = folderURL.standardizedFileURL.path
        let fileDirectory = fileURL.deletingLastPathComponent().standardizedFileURL.path
        guard fileDirectory != folderPath else { return "" }
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return fileDirectory.hasPrefix(prefix)
            ? String(fileDirectory.dropFirst(prefix.count))
            : fileDirectory
    }
}

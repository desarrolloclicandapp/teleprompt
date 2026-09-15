import Foundation
import Combine

@MainActor
final class ScriptLibrary: ObservableObject {
    @Published private(set) var scripts: [Script] = []
    @Published private(set) var storageMessage: String?

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("scripts.json")
        load()
    }

    func add(
        title: String = "Nuevo guion",
        text: String = "",
        sourcePath: String? = nil,
        sourceID: String? = nil
    ) -> Script {
        let script = Script(
            title: title.isEmpty ? "Nuevo guion" : title,
            text: text,
            sourcePath: sourcePath,
            sourceID: sourceID
        )
        scripts.insert(script, at: 0)
        save()
        return script
    }

    @discardableResult
    func importDocument(
        title: String,
        text: String,
        sourcePath: String? = nil,
        sourceID: String? = nil
    ) -> Script {
        let existingIndex = scripts.firstIndex { script in
            if let sourceID {
                return script.sourceID == sourceID
                    || (script.sourceID == nil
                        && (script.sourcePath == sourcePath
                            || (sourcePath?.hasPrefix("Carpeta local") == true
                                && script.sourcePath == nil
                                && script.text == text))
                        && script.title == title)
            }
            return script.sourceID == nil
                && script.title == title
                && script.text == text
        }

        if let existingIndex {
            var existing = scripts[existingIndex]
            existing.title = title
            existing.text = text
            existing.sourcePath = sourcePath
            existing.sourceID = sourceID
            upsert(existing)
            return existing
        }

        return add(title: title, text: text, sourcePath: sourcePath, sourceID: sourceID)
    }

    func upsert(_ script: Script) {
        var updated = script
        updated.updatedAt = .now
        if let index = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[index] = updated
        } else {
            scripts.insert(updated, at: 0)
        }
        scripts.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func delete(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        save()
    }

    func clearStorageMessage() {
        storageMessage = nil
    }

    func importTextFile(from url: URL) {
        guard let document = try? DocumentImporter.read(url: url) else { return }
        _ = importDocument(title: document.title, text: document.text)
    }

    func attachFolderBookmark(_ data: Data, to scriptID: UUID? = nil) {
        guard let scriptID, let index = scripts.firstIndex(where: { $0.id == scriptID }) else { return }
        scripts[index].sourceBookmark = data
        scripts[index].updatedAt = .now
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            scripts = [ScriptSeed.welcome]
            save()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            scripts = try JSONDecoder().decode([Script].self, from: data)
        } catch {
            let recoveryURL = fileURL.deletingLastPathComponent().appendingPathComponent(
                "scripts.corrupt.\(Int(Date().timeIntervalSince1970)).json"
            )
            do {
                try FileManager.default.moveItem(at: fileURL, to: recoveryURL)
                scripts = [ScriptSeed.welcome]
                storageMessage = String(localized: "library.recovered_corrupt")
                save()
            } catch {
                scripts = []
                storageMessage = String(localized: "library.recovery_failed")
            }
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(scripts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            storageMessage = String(localized: "library.save_failed")
        }
    }
}

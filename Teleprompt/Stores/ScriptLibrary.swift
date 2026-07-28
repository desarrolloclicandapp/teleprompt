import Foundation

@MainActor
final class ScriptLibrary: ObservableObject {
    @Published private(set) var scripts: [Script] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("scripts.json")
        load()
    }

    func add(title: String = "Nuevo guion", text: String = "") -> Script {
        let script = Script(title: title.isEmpty ? "Nuevo guion" : title, text: text)
        scripts.insert(script, at: 0)
        save()
        return script
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

    func importTextFile(from url: URL) {
        guard let document = try? DocumentImporter.read(url: url) else { return }
        _ = add(title: document.title, text: document.text)
    }

    func attachFolderBookmark(_ data: Data, to scriptID: UUID? = nil) {
        guard let scriptID, let index = scripts.firstIndex(where: { $0.id == scriptID }) else { return }
        scripts[index].sourceBookmark = data
        scripts[index].updatedAt = .now
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Script].self, from: data) else {
            scripts = [ScriptSeed.welcome]
            save()
            return
        }
        scripts = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(scripts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("No se pudo guardar la biblioteca: \(error)")
        }
    }
}

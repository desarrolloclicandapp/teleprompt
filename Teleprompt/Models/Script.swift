import Foundation

struct Script: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var sourceBookmark: Data?

    init(id: UUID = UUID(), title: String, text: String, createdAt: Date = .now, updatedAt: Date = .now, sourceBookmark: Data? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceBookmark = sourceBookmark
    }
}

enum ScriptSeed {
    static let welcome = Script(
        title: "Mi primer guion",
        text: "Bienvenido a Teleprompt.\n\nPulsa reproducir para iniciar el desplazamiento. Puedes cambiar la velocidad, el tamaño del texto y activar el modo espejo desde los controles."
    )
}


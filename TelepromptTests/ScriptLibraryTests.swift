import XCTest
@testable import Teleprompt

final class ScriptLibraryTests: XCTestCase {
    @MainActor
    func testScriptCanBeCreatedAndUpdated() {
        let library = ScriptLibrary()
        let script = library.add(title: "Prueba", text: "Hola")
        XCTAssertTrue(library.scripts.contains(script))
        var edited = script
        edited.text = "Hola mundo"
        library.upsert(edited)
        XCTAssertEqual(library.scripts.first(where: { $0.id == script.id })?.text, "Hola mundo")
        library.delete(edited)
    }
}


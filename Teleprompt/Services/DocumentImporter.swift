import Foundation
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

enum DocumentImporter {
    static let supportedTypes: [UTType] = [
        .plainText,
        .text,
        .pdf,
        UTType(filenameExtension: "md")!,
        UTType(filenameExtension: "docx")!
    ]

    static func read(url: URL) throws -> (title: String, text: String) {
        guard url.startAccessingSecurityScopedResource() else { throw ImportError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        let text = try read(data: data, fileExtension: ext)
        return try makeDocument(title: url.deletingPathExtension().lastPathComponent, text: text)
    }

    static func read(data: Data, fileExtension: String, title: String) throws -> (title: String, text: String) {
        let text = try read(data: data, fileExtension: fileExtension)
        return try makeDocument(title: title, text: text)
    }

    private static func read(data: Data, fileExtension: String) throws -> String {
        let ext = fileExtension.lowercased()
        let text: String
        switch ext {
        case "pdf": text = try readPDF(data)
        case "docx": text = try readDOCX(data)
        default: text = String(data: data, encoding: .utf8) ?? ""
        }
        return text
    }

    private static func makeDocument(title: String, text: String) throws -> (title: String, text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ImportError.emptyDocument }
        return (title, cleaned)
    }

    private static func readPDF(_ url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadableDocument }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
    }

    private static func readPDF(_ data: Data) throws -> String {
        guard let document = PDFDocument(data: data) else { throw ImportError.unreadableDocument }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
    }

    private static func readDOCX(_ url: URL) throws -> String {
        guard let archive = Archive(url: url, accessMode: .read), let entry = archive["word/document.xml"] else {
            throw ImportError.unreadableDocument
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        let parser = XMLParser(data: data)
        let delegate = DOCXTextParser()
        parser.delegate = delegate
        guard parser.parse() else { throw ImportError.unreadableDocument }
        return delegate.text
    }

    private static func readDOCX(_ data: Data) throws -> String {
        guard let archive = Archive(data: data, accessMode: .read), let entry = archive["word/document.xml"] else { throw ImportError.unreadableDocument }
        var xml = Data()
        _ = try archive.extract(entry) { xml.append($0) }
        let parser = XMLParser(data: xml)
        let delegate = DOCXTextParser()
        parser.delegate = delegate
        guard parser.parse() else { throw ImportError.unreadableDocument }
        return delegate.text
    }
}

private final class DOCXTextParser: NSObject, XMLParserDelegate {
    private(set) var text = ""
    private var insideText = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "t" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { insideText = false }
        if elementName == "p" { text += "\n" }
    }
}

enum ImportError: LocalizedError {
    case accessDenied
    case emptyDocument
    case unreadableDocument

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "No se pudo acceder al archivo seleccionado."
        case .emptyDocument: return "El documento no contiene texto legible."
        case .unreadableDocument: return "No se pudo leer este documento."
        }
    }
}

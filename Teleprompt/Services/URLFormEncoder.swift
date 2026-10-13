import Foundation

enum URLFormEncoder {
    static func encode(_ values: [String: String]) -> Data? {
        let body = values
            .sorted { $0.key < $1.key }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
        return body.data(using: .utf8)
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }
}

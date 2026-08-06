import Foundation
import SwiftUI
import UIKit

@MainActor
final class RemoteInputDiagnostics: ObservableObject {
    static let shared = RemoteInputDiagnostics()

    @Published private(set) var entries: [String] = []
    private let startedAt = Date()
    private let maximumEntries = 500

    private init() {}

    func log(_ source: String, _ message: String) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let line = String(format: "%8.3fs [%@] %@", elapsed, source, message)
        entries.append(line)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        print("[RemotePAD RAW] \(line)")
    }

    func clear() {
        entries.removeAll()
    }

    var text: String {
        entries.joined(separator: "\n")
    }
}

extension RemoteAction {
    var diagnosticsName: String {
        switch self {
        case .playPause:
            return "playPause"
        case .toggleControls:
            return "toggleControls"
        case .next:
            return "next"
        case .previous:
            return "previous"
        case .reset:
            return "reset"
        case .toggleRecording:
            return "toggleRecording"
        case .toggleRecordingPause:
            return "toggleRecordingPause"
        case .increaseSpeed:
            return "increaseSpeed"
        case .decreaseSpeed:
            return "decreaseSpeed"
        case .joystick(let x, let y):
            return String(format: "joystick x=%.3f y=%.3f", x, y)
        }
    }
}

struct RemoteInputDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var diagnostics = RemoteInputDiagnostics.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(
                    diagnostics.entries.isEmpty
                        ? "Aún no hay eventos. Pulsa A, B, X, Y y mueve el joystick."
                        : diagnostics.text
                )
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
            }
            .navigationTitle("RemotePAD RAW")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Limpiar") {
                        diagnostics.clear()
                    }
                    Button("Copiar") {
                        UIPasteboard.general.string = diagnostics.text
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

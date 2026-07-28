import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: ScriptLibrary
    @StateObject private var externalFolder = ExternalFolderAccess()
    @StateObject private var drive = DriveSyncCoordinator()
    @StateObject private var google = GoogleOAuth()
    @State private var showFolderPicker = false
    @State private var driveFolderID = ""

    var body: some View {
        Form {
            Section("Biblioteca") {
                Button {
                    if google.isConnected { google.disconnect() } else { google.connect() }
                } label: {
                    Label(google.isConnected ? "Desconectar Google Drive" : "Conectar Google Drive", systemImage: "externaldrive.connected.to.line.below")
                }
                Button { showFolderPicker = true } label: {
                    Label(externalFolder.folderName.map { "Carpeta: \($0)" } ?? "Elegir carpeta de Archivos / Google Drive", systemImage: "folder")
                }
                TextField("ID de carpeta de Google Drive", text: $driveFolderID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: driveFolderID) { _, value in drive.folderID = value.isEmpty ? nil : value }
                if externalFolder.folderName != nil {
                    Button("Desconectar carpeta", role: .destructive) { externalFolder.clear() }
                }
                Button {
                    Task { await drive.sync(library: library) }
                } label: {
                    HStack {
                        Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if drive.isSyncing { ProgressView() }
                    }
                }
                if let message = drive.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if let error = google.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Alcance del MVP") {
                Label("TXT, Markdown, PDF y DOCX", systemImage: "doc.text")
                Label("Sincronización manual desde Drive", systemImage: "arrow.down.circle")
                Label("Lector offline con velocidad manual", systemImage: "play.rectangle")
                Label("Cámara y voz avanzada: opcionales", systemImage: "ellipsis.circle")
            }
        }
        .navigationTitle("Configuración")
        .onAppear { driveFolderID = drive.folderID ?? "" }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { externalFolder.rememberFolder(url) }
        }
    }
}

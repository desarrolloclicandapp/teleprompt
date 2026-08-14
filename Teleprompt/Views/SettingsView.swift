import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: ScriptLibrary
    @EnvironmentObject private var drive: DriveSyncCoordinator
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.openURL) private var openURL
    @StateObject private var externalFolder = ExternalFolderAccess()
    @StateObject private var google = GoogleOAuth()
    @State private var showLocalFolderPicker = false
    @State private var showDriveFolderPicker = false
    @State private var openPickerAfterConnection = false

    var body: some View {
        Form {
            MonetizationStatusSection()

            Section("Google Drive") {
                Button {
                    if google.isConnected {
                        drive.clearSelectedFolder()
                        google.disconnect()
                        google.connect()
                    } else {
                        google.connect()
                    }
                } label: {
                    Label(
                        google.isConnected ? "Cambiar cuenta de Google" : "Conectar Google Drive",
                        systemImage: google.isConnected ? "person.2.circle" : "externaldrive.connected.to.line.below"
                    )
                }

                Button {
                    if google.isConnected {
                        showDriveFolderPicker = true
                    } else {
                        openPickerAfterConnection = true
                        google.connect()
                    }
                } label: {
                    Label(
                        drive.folderName.map { String(format: String(localized: "drive.folder_label_format"), $0) }
                            ?? String(localized: "drive.choose_folder"),
                        systemImage: "folder.badge.gearshape"
                    )
                }

                Button {
                    openURL(URL(string: "https://drive.google.com/drive/")!)
                } label: {
                    Label("Abrir Google Drive", systemImage: "arrow.up.forward.app")
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
            }

            Section("Archivos del iPhone") {
                Button { showLocalFolderPicker = true } label: {
                    Label(
                        externalFolder.folderName.map { String(format: String(localized: "local.folder_label_format"), $0) }
                            ?? String(localized: "local.choose_folder"),
                        systemImage: "folder"
                    )
                }
                if externalFolder.folderName != nil {
                    Button("Desconectar carpeta local", role: .destructive) { externalFolder.clear() }

                    Button {
                        Task { await externalFolder.sync(library: library) }
                    } label: {
                        HStack {
                            Label("Sincronizar carpeta local", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if externalFolder.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(externalFolder.isSyncing)
                }
            }

            if let message = externalFolder.message {
                Section {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let message = drive.message {
                Section {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = google.errorMessage {
                Section {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Funciones incluidas") {
                Label("TXT, Markdown, PDF y DOCX", systemImage: "doc.text")
                Label("Descarga manual desde Drive", systemImage: "arrow.down.circle")
                Label("Lector offline con velocidad manual", systemImage: "play.rectangle")
                Label("Cámara y grabación: opcionales", systemImage: "video")
            }

            Section("Información legal") {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("Política de privacidad", systemImage: "hand.raised.fill")
                }
            }
        }
        .navigationTitle("Configuración")
        .onChange(of: google.isConnected) { _, connected in
            if connected && openPickerAfterConnection {
                openPickerAfterConnection = false
                showDriveFolderPicker = true
            }
        }
        .fileImporter(
            isPresented: $showLocalFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                externalFolder.rememberFolder(url)
            }
        }
        .sheet(isPresented: $showDriveFolderPicker) {
            DriveFolderPickerView(drive: drive) { folder in
                drive.selectFolder(folder)
                Task { await drive.sync(library: library) }
            }
        }

    }
}

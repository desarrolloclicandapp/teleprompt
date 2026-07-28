import SwiftUI

struct DriveFolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var drive: DriveSyncCoordinator
    let onSelect: (DriveFolder) -> Void

    @State private var path: [DriveFolder] = []
    @State private var folders: [DriveFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentFolder: DriveFolder {
        path.last ?? DriveFolder(id: "root", name: "Mi unidad")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        select(currentFolder)
                    } label: {
                        Label("Usar \(currentFolder.name)", systemImage: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.mint)
                } footer: {
                    Text("Abre una carpeta para entrar en ella. Cuando estés en la carpeta deseada, pulsa Usar esta carpeta.")
                }

                if !path.isEmpty {
                    Section {
                        Button {
                            path.removeLast()
                            Task { await loadFolders() }
                        } label: {
                            Label("Carpeta anterior", systemImage: "arrow.up.left")
                        }
                    }
                }

                Section("Carpetas") {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Cargando carpetas…")
                            Spacer()
                        }
                    } else if folders.isEmpty {
                        Label("No hay subcarpetas aquí", systemImage: "folder.badge.questionmark")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(folders) { folder in
                            Button {
                                path.append(folder)
                                Task { await loadFolders() }
                            } label: {
                                Label(folder.name, systemImage: "folder.fill")
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(currentFolder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task {
                await loadFolders()
            }
        }
    }

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            folders = try await drive.listFolders(in: currentFolder.id)
        } catch {
            folders = []
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ folder: DriveFolder) {
        onSelect(folder)
        dismiss()
    }
}

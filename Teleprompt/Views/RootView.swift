import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var library: ScriptLibrary
    @State private var query = ""
    @State private var sortNewest = true
    @State private var showingNew = false
    @State private var showingImporter = false
    @State private var selectedScript: Script?
    @State private var importError: String?

    private var visibleScripts: [Script] {
        let filtered = library.scripts.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) }
        return filtered.sorted { sortNewest ? $0.updatedAt > $1.updatedAt : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var scriptGroups: [ScriptGroup] {
        Dictionary(grouping: visibleScripts, by: { $0.sourcePath ?? "Mis guiones" })
            .map { ScriptGroup(name: $0.key, scripts: $0.value) }
            .sorted { lhs, rhs in
                if lhs.name == "Mis guiones" { return true }
                if rhs.name == "Mis guiones" { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.scripts.isEmpty {
                    ContentUnavailableView("No hay guiones", systemImage: "text.book.closed", description: Text("Importa un TXT, Markdown, PDF o DOCX para empezar."))
                } else if visibleScripts.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(scriptGroups) { group in
                            Section {
                                ForEach(group.scripts) { script in
                                    scriptRow(script)
                                }
                            } header: {
                                Label("\(group.name) · \(group.scripts.count)", systemImage: "folder.fill")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Teleprompt")
            .searchable(text: $query, prompt: "Buscar guiones")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showingImporter = true } label: { Label("Importar archivos", systemImage: "doc.badge.plus") }
                        Button { showingNew = true } label: { Label("Crear guion", systemImage: "square.and.pencil") }
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { sortNewest.toggle() } label: { Image(systemName: sortNewest ? "arrow.down" : "textformat.abc") }.accessibilityLabel("Cambiar orden")
                        NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    }
                }
            }
            .sheet(item: $selectedScript) { script in ScriptEditorView(script: script) }
            .sheet(isPresented: $showingNew) { ScriptEditorView(script: library.add()) }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: DocumentImporter.supportedTypes, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    urls.forEach { url in
                        do {
                            let document = try DocumentImporter.read(url: url)
                            _ = library.add(title: document.title, text: document.text)
                        } catch { importError = error.localizedDescription }
                    }
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .alert("No se pudo importar", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("Aceptar", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "") }
        }
    }

    private func scriptRow(_ script: Script) -> some View {
        Button { selectedScript = script } label: {
            HStack(spacing: 14) {
                Image(systemName: icon(for: script.title)).font(.title3).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(script.title).font(.headline).foregroundStyle(.primary)
                    Text(script.text.replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(script.updatedAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { library.delete(script) } label: { Label("Eliminar", systemImage: "trash") }
        }
    }

    private func icon(for title: String) -> String {
        switch title.split(separator: ".").last?.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx": return "doc.text"
        default: return "text.alignleft"
        }
    }
}

private struct ScriptGroup: Identifiable {
    let name: String
    let scripts: [Script]
    var id: String { name }
}

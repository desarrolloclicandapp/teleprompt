import SwiftUI

struct RootView: View {
    @EnvironmentObject private var library: ScriptLibrary
    @State private var showingNew = false
    @State private var showingImporter = false
    @State private var selectedScript: Script?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.scripts) { script in
                        Button {
                            selectedScript = script
                        } label: {
                            ScriptRow(script: script)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { library.delete(script) } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Mis guiones")
                }
            }
            .navigationTitle("Teleprompt")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingImporter = true } label: { Image(systemName: "folder.badge.plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        Button { showingNew = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(item: $selectedScript) { script in
                ScriptEditorView(script: script)
            }
            .sheet(isPresented: $showingNew) {
                ScriptEditorView(script: library.add())
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.plainText, .text, .sourceCode], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { urls.forEach(library.importTextFile) }
            }
        }
    }
}

private struct ScriptRow: View {
    let script: Script

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.title3)
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text(script.title).font(.headline)
                Text(script.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

import SwiftUI

struct ScriptEditorView: View {
    @EnvironmentObject private var library: ScriptLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var script: Script
    @State private var showReader = false

    init(script: Script) { _script = State(initialValue: script) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Título del guion", text: $script.title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $script.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
            .navigationTitle("Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { library.upsert(script); showReader = true } label: { Image(systemName: "play.fill") }
                }
            }
            .onDisappear { library.upsert(script) }
            .fullScreenCover(isPresented: $showReader) { TeleprompterView(script: script) }
        }
    }
}


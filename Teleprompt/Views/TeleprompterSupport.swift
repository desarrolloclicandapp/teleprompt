import SwiftUI

struct ScriptHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ReaderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fontSize: Double
    @Binding var mirrorHorizontal: Bool
    @Binding var mirrorVertical: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Texto") {
                    HStack {
                        Text("Tamaño")
                        Slider(value: $fontSize, in: 16...82, step: 1)
                        Text("\(Int(fontSize))")
                            .monospacedDigit()
                            .frame(width: 34)
                    }
                }

                Section("Espejo") {
                    Toggle("Espejo horizontal", isOn: $mirrorHorizontal)
                    Toggle("Espejo vertical", isOn: $mirrorVertical)
                }
            }
            .navigationTitle("Ajustes del lector")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

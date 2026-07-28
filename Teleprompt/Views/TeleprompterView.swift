import SwiftUI

struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    let script: Script
    @State private var isPlaying = false
    @State private var speed: Double = 36
    @State private var fontSize: Double = 42
    @State private var mirrorHorizontal = false
    @State private var mirrorVertical = false
    @State private var currentLine = 0
    @State private var countdownValue = 0
    @State private var showControls = true
    @State private var showRecording = false
    @State private var showReaderSettings = false
    @State private var accumulator = 0.0

    private var lines: [String] {
        script.text.components(separatedBy: .newlines).flatMap { paragraph in
            paragraph.isEmpty ? [" "] : paragraph.split(separator: " ", omittingEmptySubsequences: false).reduce(into: [String]()) { result, word in
                if let last = result.last, last.count < 52 { result[result.count - 1] = last + " " + word }
                else { result.append(String(word)) }
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteKeyCapture { action in
                switch action {
                case .playPause: togglePlayback()
                case .next: currentLine = min(currentLine + 1, max(0, lines.count - 1))
                case .previous: currentLine = max(0, currentLine - 1)
                case .reset: currentLine = 0
                case .increaseSpeed: speed = min(140, speed + 5)
                case .decreaseSpeed: speed = max(5, speed - 5)
                }
            }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 18) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 260)
                    .padding(.bottom, 520)
                    .scaleEffect(x: mirrorHorizontal ? -1 : 1, y: mirrorVertical ? -1 : 1)
                }
                .overlay(alignment: .center) { Rectangle().fill(.mint.opacity(0.6)).frame(height: 2).allowsHitTesting(false) }
                .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
                    guard isPlaying, countdownValue == 0, currentLine < lines.count - 1 else { return }
                    accumulator += speed / 100.0 * 0.05
                    if accumulator >= 1 {
                        accumulator -= 1
                        currentLine += 1
                        withAnimation(.linear(duration: 0.05)) { proxy.scrollTo(currentLine, anchor: .center) }
                    }
                }
            }

            if countdownValue > 0 { Text("\(countdownValue)").font(.system(size: 120, weight: .bold, design: .rounded)).foregroundStyle(.mint) }
            if showControls { controls }
        }
        .statusBarHidden(!showControls)
        .onTapGesture { showControls.toggle() }
        .fullScreenCover(isPresented: $showRecording) { RecordingView(script: script) }
        .sheet(isPresented: $showReaderSettings) { ReaderSettingsView(speed: $speed, fontSize: $fontSize, mirrorHorizontal: $mirrorHorizontal, mirrorVertical: $mirrorVertical) }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                Spacer()
                Text(script.title).font(.headline).lineLimit(1)
                Spacer()
                Button { showControls = false } label: { Image(systemName: "eye.slash") }
            }
            HStack {
                Text("\(Int(speed))").monospacedDigit().frame(width: 34)
                Slider(value: $speed, in: 5...140).accessibilityLabel("Velocidad")
                Image(systemName: "speedometer")
            }
            HStack(spacing: 18) {
                Button { showReaderSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                Button { currentLine = 0; accumulator = 0 } label: { Image(systemName: "backward.end") }
                Button { showRecording = true } label: { Image(systemName: "video") }
                Spacer()
                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 52, height: 52)
                }.buttonStyle(.borderedProminent)
            }
            ProgressView(value: Double(currentLine), total: Double(max(1, lines.count))).tint(.mint)
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.86))
    }

    private func togglePlayback() {
        if isPlaying { isPlaying = false; return }
        countdownValue = 3
        Task {
            for value in stride(from: 3, through: 1, by: -1) {
                countdownValue = value
                try? await Task.sleep(for: .seconds(1))
            }
            countdownValue = 0
            isPlaying = true
        }
    }
}

private struct ReaderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var speed: Double
    @Binding var fontSize: Double
    @Binding var mirrorHorizontal: Bool
    @Binding var mirrorVertical: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Texto") {
                    HStack { Text("Tamaño"); Slider(value: $fontSize, in: 20...100); Text("\(Int(fontSize))") }
                }
                Section("Espejo") {
                    Toggle("Espejo horizontal", isOn: $mirrorHorizontal)
                    Toggle("Espejo vertical", isOn: $mirrorVertical)
                }
            }
            .navigationTitle("Ajustes del lector")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

import SwiftUI

struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    let script: Script

    @StateObject private var recorder = CameraRecorder()
    @StateObject private var mediaRemote = MediaRemoteController()
    @State private var isPlaying = false
    @State private var speed: Double = 100
    @State private var fontSize: Double = 42
    @State private var mirrorHorizontal = false
    @State private var mirrorVertical = false
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var countdownValue = 0
    @State private var showControls = true
    @State private var showCamera = false
    @State private var showReaderSettings = false
    @State private var controlsOffset: CGFloat = 0

    private let minimumSpeed = 30.0
    private let maximumSpeed = 600.0

    private var maxScrollOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    private var progress: Double {
        guard maxScrollOffset > 0 else { return 0 }
        return min(1, max(0, Double(scrollOffset / maxScrollOffset)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showCamera {
                CameraPreview(session: recorder.session)
                    .ignoresSafeArea()
                    .transition(.opacity)
                Color.black.opacity(0.34).ignoresSafeArea()
            }

            RemoteKeyCapture(onAction: handleRemoteAction)
                .frame(width: 1, height: 1)
                .opacity(0.01)

            scriptReader

            if showCamera { cameraStatusBar }
            if countdownValue > 0 {
                Text("\(countdownValue)")
                    .font(.system(size: 118, weight: .bold, design: .rounded))
                    .foregroundStyle(.mint)
                    .shadow(color: .black, radius: 14)
            }
            if showControls {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    controls
                        .offset(y: controlsOffset)
                        .contentShape(Rectangle())
                        .gesture(controlsDragGesture)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaPadding(.bottom, 4)
            }
        }
        .statusBarHidden(!showControls)
        .sheet(isPresented: $showReaderSettings) {
            ReaderSettingsView(
                fontSize: $fontSize,
                mirrorHorizontal: $mirrorHorizontal,
                mirrorVertical: $mirrorVertical
            )
        }
        .task(id: showCamera) {
            if showCamera { await recorder.prepare() }
        }
        .onAppear {
            mediaRemote.onAction = handleRemoteAction
            mediaRemote.start()
        }
        .onDisappear {
            mediaRemote.stop()
            if recorder.isRecording { recorder.toggleRecording() }
            recorder.stopSession()
        }
        .animation(.easeInOut(duration: 0.2), value: showCamera)
    }

    private var scriptReader: some View {
        GeometryReader { viewport in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: max(150, viewport.size.height * 0.34))

                    Text(script.text)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(max(6, fontSize * 0.18))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 26)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: max(260, viewport.size.height * 0.58))
                }
                .scaleEffect(x: mirrorHorizontal ? -1 : 1, y: mirrorVertical ? -1 : 1)
                .offset(y: -scrollOffset)
                .background(
                    GeometryReader { content in
                        Color.clear.preference(
                            key: ScriptHeightPreferenceKey.self,
                            value: content.size.height
                        )
                    }
                )
            }
            .scrollDisabled(true)
            .clipped()
            .overlay {
                Rectangle()
                    .fill(.mint.opacity(0.86))
                    .frame(height: 2)
                    .shadow(color: .mint.opacity(0.65), radius: 6)
                    .allowsHitTesting(false)
            }
            .onAppear { viewportHeight = viewport.size.height }
            .onChange(of: viewport.size.height) { _, height in
                viewportHeight = height
                scrollOffset = min(scrollOffset, max(0, contentHeight - height))
            }
            .onPreferenceChange(ScriptHeightPreferenceKey.self) { height in
                contentHeight = height
                scrollOffset = min(scrollOffset, max(0, height - viewportHeight))
            }
            .onTapGesture { showControls = true }
            .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
                advanceScroll()
            }
        }
    }

    private var cameraStatusBar: some View {
        VStack {
            HStack(spacing: 12) {
                Label(
                    recorder.isRecording ? "Grabando" : "Cámara activa",
                    systemImage: recorder.isRecording ? "record.circle.fill" : "video.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(recorder.isRecording ? .red : .white)

                Spacer()

                Button {
                    if recorder.isRecording { recorder.toggleRecording() }
                    showCamera = false
                    recorder.stopSession()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Cerrar cámara")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(.black.opacity(0.72))
            Spacer()
        }
        .zIndex(3)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(.white.opacity(0.42))
                .frame(width: 42, height: 5)
                .padding(.top, 2)
                .accessibilityLabel("Panel de controles. Arrastra para moverlo")

            HStack(spacing: 14) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 2) {
                    Text(script.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(Int(speed)) ppm · \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { showReaderSettings = true } label: {
                    Image(systemName: "textformat.size")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ajustes del lector")

                Button { showControls = false } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ocultar controles")
            }

            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(.secondary)
                Slider(value: $speed, in: minimumSpeed...maximumSpeed, step: 1)
                    .tint(.mint)
                Image(systemName: "hare.fill")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Velocidad")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("30–600 ppm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button { resetReader() } label: {
                    Label("Inicio", systemImage: "backward.end.fill")
                }
                .buttonStyle(.bordered)

                Button { showCamera.toggle() } label: {
                    Label(showCamera ? "Cámara" : "Grabar", systemImage: showCamera ? "video.fill" : "video")
                }
                .buttonStyle(.bordered)

                if showCamera {
                    Button { recorder.toggleRecording() } label: {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.isRecording ? .red : .mint)
                    .accessibilityLabel(recorder.isRecording ? "Detener grabación" : "Iniciar grabación")
                }

                Spacer(minLength: 0)

                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .accessibilityLabel(isPlaying ? "Pausar lectura" : "Iniciar lectura")
            }

            ProgressView(value: progress)
                .tint(.mint)

            if recorder.savedToPhotos {
                Label("Video guardado en Fotos", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
            if let message = recorder.authorizationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .foregroundStyle(.white)
        .background(.black.opacity(0.9))
    }

    private var controlsDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                controlsOffset = min(260, max(-260, value.translation.height))
            }
    }

    private func advanceScroll() {
        guard isPlaying, countdownValue == 0, maxScrollOffset > 0 else { return }
        let pointsPerSecond = speed * 0.12
        scrollOffset = min(maxScrollOffset, scrollOffset + CGFloat(pointsPerSecond / 60.0))
        if scrollOffset >= maxScrollOffset - 0.5 {
            isPlaying = false
            if recorder.isRecording { recorder.toggleRecording() }
        }
    }

    private func handleRemoteAction(_ action: RemoteAction) {
        switch action {
        case .playPause: togglePlayback()
        case .next:
            scrollOffset = min(maxScrollOffset, scrollOffset + max(180, viewportHeight * 0.38))
        case .previous:
            scrollOffset = max(0, scrollOffset - max(180, viewportHeight * 0.38))
        case .reset: resetReader()
        case .increaseSpeed: speed = min(maximumSpeed, speed + 5)
        case .decreaseSpeed: speed = max(minimumSpeed, speed - 5)
        }
    }

    private func resetReader() {
        isPlaying = false
        countdownValue = 0
        scrollOffset = 0
    }

    private func togglePlayback() {
        if isPlaying {
            isPlaying = false
            return
        }
        if scrollOffset >= maxScrollOffset - 0.5 { scrollOffset = 0 }
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

private struct ScriptHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReaderSettingsView: View {
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
                        Slider(value: $fontSize, in: 22...82, step: 1)
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
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

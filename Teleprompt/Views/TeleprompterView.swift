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
    @State private var panelSize: CGSize = .zero
    @State private var panelCenter: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var layoutIsLandscape = false
    @State private var panelDragStart: CGPoint?
    @State private var resizeStartSize: CGSize?
    @State private var textDragStartOffset: CGFloat?

    private let minimumSpeed = 30.0
    private let maximumSpeed = 600.0

    private var maxScrollOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    private var progress: Double {
        guard maxScrollOffset > 0 else { return 0 }
        return min(1, max(0, Double(scrollOffset / maxScrollOffset)))
    }

    private var isLandscape: Bool {
        canvasSize.width > canvasSize.height
    }

    var body: some View {
        GeometryReader { canvas in
            ZStack {
                Color.black.ignoresSafeArea()

                if showCamera {
                    cameraPreview(for: canvas.size)
                        .transition(.opacity)
                    Color.black.opacity(0.34)
                        .frame(
                            width: canvas.size.width > canvas.size.height ? canvas.size.width * 0.58 : canvas.size.width,
                            height: canvas.size.height
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .ignoresSafeArea()
                }

                RemoteKeyCapture(onAction: handleRemoteAction)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                if panelSize != .zero {
                    readerPanel
                        .frame(width: panelSize.width, height: panelSize.height)
                        .position(panelCenter)
                        .zIndex(1)
                }

                if showCamera { cameraStatusBar }
                if countdownValue > 0 {
                    Text("\(countdownValue)")
                        .font(.system(size: 118, weight: .bold, design: .rounded))
                        .foregroundStyle(.mint)
                        .shadow(color: .black, radius: 14)
                        .zIndex(4)
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
                    .zIndex(5)
                }
            }
            .onAppear {
                updatePanelLayout(for: canvas.size, forceReset: true)
            }
            .onChange(of: canvas.size) { _, size in
                updatePanelLayout(for: size)
            }
            .onChange(of: showCamera) { _, _ in
                updatePanelLayout(for: canvas.size, forceReset: true)
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

    private var readerPanel: some View {
        ZStack(alignment: .top) {
            scriptReader

            panelMoveHandle
                .padding(.horizontal, 12)
                .zIndex(2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(.black.opacity(showCamera ? 0.62 : 0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
                .zIndex(3)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private func cameraPreview(for size: CGSize) -> some View {
        let cameraWidth = size.width > size.height ? size.width * 0.58 : size.width
        return CameraPreview(session: recorder.session)
            .frame(width: cameraWidth, height: size.height)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .ignoresSafeArea()
    }

    private var panelMoveHandle: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.caption.weight(.bold))
            Text("Mover texto")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.black.opacity(0.45), in: Capsule())
        .contentShape(Rectangle())
        .gesture(panelDragGesture)
        .accessibilityLabel("Mover el panel de texto")
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 42, height: 42)
            .background(.black.opacity(0.55), in: Circle())
            .padding(8)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
            .accessibilityLabel("Cambiar tamaño del panel de texto")
    }

    private var scriptReader: some View {
        GeometryReader { viewport in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: max(44, viewport.size.height * 0.12))

                    Text(script.text)
                        .font(.system(size: responsiveFontSize(for: viewport.size.width), weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(max(4, responsiveFontSize(for: viewport.size.width) * 0.18))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, min(26, viewport.size.width * 0.08))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer().frame(height: max(160, viewport.size.height * 0.55))
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
            .simultaneousGesture(textScrollGesture)
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

    private func responsiveFontSize(for panelWidth: CGFloat) -> CGFloat {
        min(82, max(22, fontSize * panelWidth / 380))
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

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = panelDragStart ?? panelCenter
                panelDragStart = start
                panelCenter = boundedPanelCenter(
                    CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    ),
                    panelSize: panelSize,
                    canvasSize: canvasSize
                )
            }
            .onEnded { _ in
                panelDragStart = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = resizeStartSize ?? panelSize
                resizeStartSize = start

                if isLandscape {
                    let nonCameraWidth = canvasSize.width * 0.42
                    let maximumSide = max(180, min(nonCameraWidth - 24, canvasSize.height - 24))
                    let side = min(maximumSide, max(180, start.width + value.translation.width))
                    panelSize = CGSize(width: side, height: side)
                } else {
                    let maximumWidth = max(180, canvasSize.width - 24)
                    let maximumHeight = max(220, canvasSize.height - 24)
                    panelSize = CGSize(
                        width: min(maximumWidth, max(180, start.width + value.translation.width)),
                        height: min(maximumHeight, max(220, start.height + value.translation.height))
                    )
                }
                panelCenter = boundedPanelCenter(panelCenter, panelSize: panelSize, canvasSize: canvasSize)
            }
            .onEnded { _ in
                resizeStartSize = nil
            }
    }

    private var textScrollGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = textDragStartOffset ?? scrollOffset
                textDragStartOffset = start
                isPlaying = false
                scrollOffset = min(
                    maxScrollOffset,
                    max(0, start - value.translation.height)
                )
            }
            .onEnded { _ in
                textDragStartOffset = nil
            }
    }

    private func updatePanelLayout(for size: CGSize, forceReset: Bool = false) {
        guard size.width > 1, size.height > 1 else { return }

        let landscape = size.width > size.height
        let orientationChanged = landscape != layoutIsLandscape
        canvasSize = size
        layoutIsLandscape = landscape

        if forceReset || panelSize == .zero || orientationChanged {
            panelSize = defaultPanelSize(for: size, isLandscape: landscape)
            panelCenter = defaultPanelCenter(for: size, panelSize: panelSize, isLandscape: landscape)
        } else {
            panelSize = limitedPanelSize(panelSize, for: size, isLandscape: landscape)
            panelCenter = boundedPanelCenter(panelCenter, panelSize: panelSize, canvasSize: size)
        }
    }

    private func defaultPanelSize(for size: CGSize, isLandscape: Bool) -> CGSize {
        if isLandscape {
            let nonCameraWidth = size.width * 0.42
            let side = min(
                max(180, nonCameraWidth - 24),
                max(180, min(size.height * 0.82, nonCameraWidth - 24))
            )
            return CGSize(width: side, height: side)
        }

        return CGSize(
            width: min(max(220, size.width - 24), 420),
            height: min(max(240, size.height * 0.42), max(240, size.height - 24))
        )
    }

    private func limitedPanelSize(_ size: CGSize, for canvas: CGSize, isLandscape: Bool) -> CGSize {
        if isLandscape {
            let nonCameraWidth = canvas.width * 0.42
            let maximumSide = max(180, min(nonCameraWidth - 24, canvas.height - 24))
            let side = min(maximumSide, max(180, size.width))
            return CGSize(width: side, height: side)
        }

        return CGSize(
            width: min(max(180, canvas.width - 24), max(180, size.width)),
            height: min(max(220, canvas.height - 24), max(220, size.height))
        )
    }

    private func defaultPanelCenter(for canvas: CGSize, panelSize: CGSize, isLandscape: Bool) -> CGPoint {
        let topInset: CGFloat = showCamera ? 68 : 18
        if isLandscape {
            let nonCameraWidth = canvas.width * 0.42
            return boundedPanelCenter(
                CGPoint(x: nonCameraWidth - panelSize.width / 2 - 12, y: topInset + panelSize.height / 2),
                panelSize: panelSize,
                canvasSize: canvas
            )
        }

        return boundedPanelCenter(
            CGPoint(x: canvas.width / 2, y: topInset + panelSize.height / 2),
            panelSize: panelSize,
            canvasSize: canvas
        )
    }

    private func boundedPanelCenter(_ center: CGPoint, panelSize: CGSize, canvasSize: CGSize) -> CGPoint {
        let minimumX = panelSize.width / 2 + 8
        let horizontalLimit = canvasSize.width > canvasSize.height ? canvasSize.width * 0.42 : canvasSize.width
        let maximumX = max(minimumX, horizontalLimit - panelSize.width / 2 - 8)
        let minimumY = panelSize.height / 2 + 8
        let maximumY = max(minimumY, canvasSize.height - panelSize.height / 2 - 8)
        return CGPoint(
            x: min(max(center.x, minimumX), maximumX),
            y: min(max(center.y, minimumY), maximumY)
        )
    }

    private func advanceScroll() {
        guard isPlaying, countdownValue == 0, maxScrollOffset > 0 else { return }
        let pointsPerSecond = speed * 0.12
        scrollOffset = min(maxScrollOffset, scrollOffset + CGFloat(pointsPerSecond / 60.0))
        if scrollOffset >= maxScrollOffset - 0.5 {
            isPlaying = false
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

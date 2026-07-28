import SwiftUI
import UIKit

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
    @State private var panelSize: CGSize = .zero
    @State private var panelCenter: CGPoint = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var layoutIsLandscape = false
    @State private var panelDragStart: CGPoint?
    @State private var resizeStartSize: CGSize?
    @State private var textDragStartOffset: CGFloat?
    @State private var cameraSideIsTrailing = true

    private let minimumSpeed = 30.0
    private let maximumSpeed = 600.0
    private let portraitControlHeight: CGFloat = 228

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

    private var landscapeControlSide: CGFloat {
        min(360, max(280, canvasSize.height - 24))
    }

    private var currentInterfaceOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .portrait
    }

    var body: some View {
        GeometryReader { canvas in
            let landscape = canvas.size.width > canvas.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if showCamera {
                    cameraPreview(
                        for: canvas.size,
                        isLandscape: landscape,
                        interfaceOrientation: currentInterfaceOrientation
                    )
                        .transition(.opacity)
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

                if countdownValue > 0 {
                    Text("\(countdownValue)")
                        .font(.system(size: 118, weight: .bold, design: .rounded))
                        .foregroundStyle(.mint)
                        .shadow(color: .black, radius: 14)
                        .zIndex(4)
                }
                if showControls {
                    controls
                        .frame(
                            width: landscape ? landscapeControlSide : nil,
                            height: landscape ? landscapeControlSide : portraitControlHeight
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: (landscape && showCamera)
                                ? (cameraSideIsTrailing ? .bottomLeading : .bottomTrailing)
                                : .bottom
                        )
                        .padding(.leading, landscape && cameraSideIsTrailing ? 8 : 0)
                        .padding(.trailing, landscape && !cameraSideIsTrailing ? 8 : 0)
                        .padding(.bottom, 4)
                    .zIndex(5)
                }
            }
            .onAppear {
                updatePanelLayout(for: canvas.size, safeAreaInsets: canvas.safeAreaInsets, forceReset: true)
            }
            .onChange(of: canvas.size) { _, size in
                updatePanelLayout(for: size, safeAreaInsets: canvas.safeAreaInsets)
            }
            .onChange(of: canvas.safeAreaInsets) { _, insets in
                updatePanelLayout(for: canvas.size, safeAreaInsets: insets)
            }
            .onChange(of: showCamera) { _, _ in
                updatePanelLayout(for: canvas.size, safeAreaInsets: canvas.safeAreaInsets, forceReset: true)
            }
        }
        .ignoresSafeArea()
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
        .overlay(alignment: .trailing) {
            widthResizeHandle
                .zIndex(3)
        }
        .overlay(alignment: .bottom) {
            heightResizeHandle
                .zIndex(3)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private func cameraPreview(
        for size: CGSize,
        isLandscape: Bool,
        interfaceOrientation: UIInterfaceOrientation
    ) -> some View {
        let rotation: Angle
        switch interfaceOrientation {
        case .landscapeLeft:
            rotation = .degrees(90)
        case .landscapeRight:
            rotation = .degrees(-90)
        default:
            rotation = .zero
        }
        let rotatedFrame = isLandscape
            ? CGSize(width: size.height, height: size.width)
            : size

        return CameraPreview(session: recorder.session)
            .frame(width: rotatedFrame.width, height: rotatedFrame.height)
            .rotationEffect(rotation)
            .frame(width: size.width, height: size.height)
            .clipped()
            .ignoresSafeArea()
    }

    private var panelMoveHandle: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.caption.weight(.bold))
        .foregroundStyle(.white.opacity(0.8))
        .frame(width: 34, height: 34)
        .background(.black.opacity(0.45), in: Circle())
        .contentShape(Rectangle())
        .gesture(panelDragGesture)
        .accessibilityLabel("Mover el panel de texto")
    }

    private var resizeHandle: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 10, height: 10)
        }
        .frame(width: 52, height: 52)
            .contentShape(Rectangle())
            .gesture(resizeGesture(resizeWidth: true, resizeHeight: true))
            .accessibilityLabel("Cambiar ancho y alto del panel de texto")
    }

    private var widthResizeHandle: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 18, height: 4)
        }
        .frame(width: 48, height: 84)
            .contentShape(Rectangle())
            .gesture(resizeGesture(resizeWidth: true, resizeHeight: false))
            .accessibilityLabel("Cambiar el ancho del panel de texto")
    }

    private var heightResizeHandle: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 4, height: 18)
        }
        .frame(width: 84, height: 48)
            .contentShape(Rectangle())
            .gesture(resizeGesture(resizeWidth: false, resizeHeight: true))
            .accessibilityLabel("Cambiar el alto del panel de texto")
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

    private var controls: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.white.opacity(0.32))
                .frame(width: 52, height: 6)
                .frame(height: 24)
                .accessibilityLabel("Panel de controles fijo")

            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Cerrar teleprompter")

                Button { resetReader() } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Volver al inicio")

                Button { toggleCamera() } label: {
                    Image(systemName: showCamera ? "video.fill" : "video")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(showCamera ? "Apagar cámara" : "Encender cámara")

                if showCamera {
                    Button {
                        recorder.toggleRecording(interfaceOrientation: currentInterfaceOrientation)
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                            .font(.title3)
                            .frame(width: 42, height: 42)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.isRecording ? .red : .mint)
                    .accessibilityLabel(recorder.isRecording ? "Detener grabación" : "Iniciar grabación")
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button { showReaderSettings = true } label: {
                    Image(systemName: "textformat.size")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ajustes del lector")

                Button { showControls = false } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ocultar controles")

                Spacer(minLength: 0)

                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(width: 46, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .accessibilityLabel(isPlaying ? "Pausar lectura" : "Iniciar lectura")
            }

            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(.secondary)

                Slider(value: $speed, in: minimumSpeed...maximumSpeed, step: 1)
                    .tint(.mint)
                    .accessibilityLabel("Velocidad de lectura")
                    .accessibilityValue("\(Int(speed)) palabras por minuto")

                Image(systemName: "hare.fill")
                    .foregroundStyle(.secondary)

                Text("\(Int(speed))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(minWidth: 34, alignment: .trailing)
                    .accessibilityLabel("\(Int(speed)) palabras por minuto")
            }

            ProgressView(value: progress)
                .tint(.mint)

            if recorder.savedToPhotos {
                Label("Video guardado en Fotos", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.mint)
                    .lineLimit(1)
            }
            if let message = recorder.authorizationMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .foregroundStyle(.white)
        .background(.black.opacity(0.9))
        .clipped()
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

    private func resizeGesture(resizeWidth: Bool, resizeHeight: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = resizeStartSize ?? panelSize
                resizeStartSize = start

                let horizontalLimit = canvasSize.width
                let maximumWidth = max(180, horizontalLimit - 24)
                let minimumHeight: CGFloat = isLandscape ? 180 : 220
                let maximumHeight = max(minimumHeight, canvasSize.height - 24)

                if isLandscape {
                    let requestedSide: CGFloat
                    if resizeWidth && resizeHeight {
                        requestedSide = start.width + max(value.translation.width, value.translation.height)
                    } else if resizeWidth {
                        requestedSide = start.width + value.translation.width
                    } else {
                        requestedSide = start.height + value.translation.height
                    }
                    let maximumSide = max(180, min(maximumWidth, maximumHeight))
                    let side = min(maximumSide, max(180, requestedSide))
                    panelSize = CGSize(width: side, height: side)
                    panelCenter = boundedPanelCenter(panelCenter, panelSize: panelSize, canvasSize: canvasSize)
                    return
                }

                let requestedWidth = resizeWidth
                    ? start.width + value.translation.width
                    : start.width
                let requestedHeight = resizeHeight
                    ? start.height + value.translation.height
                    : start.height

                panelSize = CGSize(
                    width: min(maximumWidth, max(180, requestedWidth)),
                    height: min(maximumHeight, max(minimumHeight, requestedHeight))
                )
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

    private func updatePanelLayout(
        for size: CGSize,
        safeAreaInsets: EdgeInsets,
        forceReset: Bool = false
    ) {
        guard size.width > 1, size.height > 1 else { return }

        let landscape = size.width > size.height
        let orientationChanged = landscape != layoutIsLandscape
        let sideChanged = landscape && (safeAreaInsets.trailing >= safeAreaInsets.leading) != cameraSideIsTrailing
        if landscape {
            cameraSideIsTrailing = safeAreaInsets.trailing >= safeAreaInsets.leading
        }
        canvasSize = size
        layoutIsLandscape = landscape

        if forceReset || panelSize == .zero || orientationChanged || sideChanged {
            panelSize = defaultPanelSize(for: size, isLandscape: landscape)
            panelCenter = defaultPanelCenter(
                for: size,
                panelSize: panelSize,
                isLandscape: landscape,
                safeAreaInsets: safeAreaInsets
            )
        } else {
            panelSize = limitedPanelSize(panelSize, for: size, isLandscape: landscape)
            panelCenter = boundedPanelCenter(panelCenter, panelSize: panelSize, canvasSize: size)
        }
    }

    private func defaultPanelSize(for size: CGSize, isLandscape: Bool) -> CGSize {
        if isLandscape {
            let side = min(
                max(180, size.width - 24),
                max(180, min(size.height * 0.82, size.width - 24))
            )
            return CGSize(width: side, height: side)
        }

        return CGSize(
            width: min(max(220, size.width - 24), 420),
            height: min(max(240, size.height * 0.42), max(240, size.height - 24))
        )
    }

    private func limitedPanelSize(_ size: CGSize, for canvas: CGSize, isLandscape: Bool) -> CGSize {
        let horizontalLimit = canvas.width
        let minimumHeight: CGFloat = isLandscape ? 180 : 220

        if isLandscape {
            let maximumSide = max(180, min(horizontalLimit - 24, canvas.height - 24))
            let side = min(maximumSide, max(180, min(size.width, size.height)))
            return CGSize(width: side, height: side)
        }

        return CGSize(
            width: min(max(180, horizontalLimit - 24), max(180, size.width)),
            height: min(max(minimumHeight, canvas.height - 24), max(minimumHeight, size.height))
        )
    }

    private func defaultPanelCenter(
        for canvas: CGSize,
        panelSize: CGSize,
        isLandscape: Bool,
        safeAreaInsets: EdgeInsets
    ) -> CGPoint {
        let topInset: CGFloat = showCamera
            ? max(12, safeAreaInsets.top + 8)
            : 18
        if isLandscape && showCamera {
            let x = cameraSideIsTrailing
                ? canvas.width - panelSize.width / 2 - 12
                : panelSize.width / 2 + 12
            return boundedPanelCenter(
                CGPoint(x: x, y: topInset + panelSize.height / 2),
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
        let panelHalfWidth = panelSize.width / 2
        let minimumX: CGFloat
        let maximumX: CGFloat
        minimumX = panelHalfWidth + 8
        maximumX = max(minimumX, canvasSize.width - panelHalfWidth - 8)
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

    private func toggleCamera() {
        if showCamera {
            if recorder.isRecording { recorder.toggleRecording() }
            showCamera = false
            recorder.stopSession()
        } else {
            showCamera = true
        }
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

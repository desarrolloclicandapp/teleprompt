import SwiftUI
import UIKit

extension TeleprompterView {
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

                RemoteKeyCapture { action in
                    RemoteInputDiagnostics.shared.log("KEYBOARD", action.diagnosticsName)
                    handleRemoteAction(action)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)

                RemoteGamepadCapture { action in
                    RemoteInputDiagnostics.shared.log("GAMEPAD", action.diagnosticsName)
                    handleRemoteAction(action)
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)

                RemoteRawGamepadProbe()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                RemoteMediaCommandCapture { action in
                    RemoteInputDiagnostics.shared.log("MEDIA", action.diagnosticsName)
                    handleRemoteAction(action)
                }
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

                    Button {
                        showRemoteDiagnostics = true
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.72), in: Circle())
                            .overlay {
                                Circle().stroke(.white.opacity(0.25), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .zIndex(20)
                    .accessibilityLabel("Abrir diagnóstico RemotePAD")
                }

                if recorder.isProcessing {
                    processingVideoOverlay
                        .zIndex(100)
                        .transition(.opacity)
                }
            }
            .onAppear {
                updatePanelLayout(
                    for: canvas.size,
                    safeAreaInsets: canvas.safeAreaInsets,
                    forceReset: true
                )
            }
            .onChange(of: canvas.size) { _, size in
                updatePanelLayout(for: size, safeAreaInsets: canvas.safeAreaInsets)
            }
            .onChange(of: canvas.safeAreaInsets) { _, insets in
                updatePanelLayout(for: canvas.size, safeAreaInsets: insets)
            }
            .onChange(of: showCamera) { _, _ in
                updatePanelLayout(
                    for: canvas.size,
                    safeAreaInsets: canvas.safeAreaInsets,
                    forceReset: true
                )
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
        .sheet(isPresented: $showRemoteDiagnostics) {
            RemoteInputDiagnosticsView()
        }
        .task(id: showCamera) {
            if showCamera {
                await recorder.prepare()
            }
        }
        .onDisappear {
            cancelCountdown()
            joystickInput = .zero

            Task {
                await recorder.stopRecordingSessionAndWait()
                recorder.stopSession()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCamera)
        .animation(.easeInOut(duration: 0.15), value: recorder.isProcessing)
    }

    var processingVideoOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

                Text("Procesando video")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Uniendo segmentos y guardando en Fotos…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Procesando y guardando el video. Los controles están temporalmente bloqueados.")
        .accessibilityAddTraits(.isModal)
    }

    var readerPanel: some View {
        ZStack(alignment: .top) {
            scriptReader

            panelMoveHandle
                .padding(.horizontal, 12)
                .zIndex(2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            .black.opacity(showCamera ? 0.62 : 0.9),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeHandle.zIndex(3)
        }
        .overlay(alignment: .trailing) {
            widthResizeHandle.zIndex(3)
        }
        .overlay(alignment: .bottom) {
            heightResizeHandle.zIndex(3)
        }
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    func cameraPreview(
        for size: CGSize,
        isLandscape: Bool,
        interfaceOrientation: UIInterfaceOrientation
    ) -> some View {
        let rotation = cameraDisplayRotation(for: interfaceOrientation)
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

    func cameraDisplayRotation(for interfaceOrientation: UIInterfaceOrientation) -> Angle {
        switch interfaceOrientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        default:
            return .zero
        }
    }

    var panelMoveHandle: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 34, height: 34)
            .background(.black.opacity(0.45), in: Circle())
            .contentShape(Rectangle())
            .gesture(panelDragGesture)
            .accessibilityLabel("Mover el panel de texto")
    }

    var resizeHandle: some View {
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

    var widthResizeHandle: some View {
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

    var heightResizeHandle: some View {
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
}

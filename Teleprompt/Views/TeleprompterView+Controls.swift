import Combine
import SwiftUI
import UIKit

extension TeleprompterView {
    var scriptReader: some View {
        GeometryReader { viewport in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: max(44, viewport.size.height * 0.12))

                    Text(script.text)
                        .font(
                            .system(
                                size: responsiveFontSize(for: viewport.size.width),
                                weight: .medium,
                                design: .rounded
                            )
                        )
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
            .onAppear {
                viewportHeight = viewport.size.height
            }
            .onChange(of: viewport.size.height) { _, height in
                viewportHeight = height
                scrollOffset = min(scrollOffset, max(0, contentHeight - height))
            }
            .onPreferenceChange(ScriptHeightPreferenceKey.self) { height in
                contentHeight = height
                scrollOffset = min(scrollOffset, max(0, height - viewportHeight))
            }
            .onTapGesture {
                guard !recorder.isProcessing else { return }
                showControls = true
            }
            .onReceive(
                Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
            ) { _ in
                advanceScroll()
            }
        }
    }

    func responsiveFontSize(for panelWidth: CGFloat) -> CGFloat {
        min(82, max(16, fontSize * panelWidth / 380))
    }

    var controls: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.white.opacity(0.32))
                .frame(width: 52, height: 6)
                .frame(height: 24)
                .accessibilityLabel("Panel de controles fijo")

            HStack(spacing: 8) {
                if recorder.isRecording && showCamera && !recorder.isProcessing {
                    Button {
                        guard recorder.isRecording,
                              showCamera,
                              !recorder.isProcessing else { return }
                        recorder.togglePauseResume(
                            interfaceOrientation: currentInterfaceOrientation
                        )
                    } label: {
                        Image(
                            systemName: recorder.isPaused
                                ? "play.fill"
                                : "pause.fill"
                        )
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .tint(recorder.isPaused ? .green : .yellow)
                    .accessibilityLabel(
                        recorder.isPaused
                            ? "Reanudar grabación"
                            : "Pausar grabación"
                    )
                }

                Button {
                    guard !recorder.isProcessing else { return }
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Cerrar teleprompter")

                Button {
                    resetReader()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Volver al inicio")

                Button {
                    toggleCamera()
                } label: {
                    Image(systemName: showCamera ? "video.fill" : "video")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(showCamera ? "Apagar cámara" : "Encender cámara")

                if showCamera {
                    Button {
                        guard !recorder.isProcessing else { return }
                        recorder.toggleRecording(
                            interfaceOrientation: currentInterfaceOrientation
                        )
                    } label: {
                        Image(
                            systemName: recorder.isRecording
                                ? "stop.fill"
                                : "record.circle.fill"
                        )
                        .font(.title3)
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.isRecording ? .red : .mint)
                    .accessibilityLabel(
                        recorder.isRecording
                            ? "Detener grabación"
                            : "Iniciar grabación"
                    )
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    guard !recorder.isProcessing else { return }
                    showReaderSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ajustes del lector")

                Button {
                    guard !recorder.isProcessing else { return }
                    showControls = false
                } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: 42, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Ocultar controles")

                Spacer(minLength: 0)

                Button {
                    togglePlayback()
                } label: {
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

                Slider(
                    value: Binding(
                        get: { Double(speedLevel) },
                        set: { level in
                            speed = speedForLevel(Int(level.rounded()))
                        }
                    ),
                    in: 1...Double(speedLevelCount),
                    step: 1
                )
                    .tint(.mint)
                    .accessibilityLabel("Velocidad de lectura")
                    .accessibilityValue(
                        "Nivel \(speedLevel) de \(speedLevelCount), \(Int(speed)) palabras por minuto"
                    )

                Image(systemName: "hare.fill")
                    .foregroundStyle(.secondary)

                Text("\(Int(speed))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(minWidth: 42, alignment: .trailing)
                    .accessibilityLabel(
                        "Nivel \(speedLevel) de \(speedLevelCount), \(Int(speed)) palabras por minuto"
                    )
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
        .disabled(recorder.isProcessing)
    }

    var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !recorder.isProcessing else { return }

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

    func resizeGesture(resizeWidth: Bool, resizeHeight: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !recorder.isProcessing else { return }

                let start = resizeStartSize ?? panelSize
                resizeStartSize = start

                let horizontalLimit = isLandscape && showCamera
                    ? canvasSize.width * 0.5
                    : canvasSize.width
                let maximumWidth = max(180, horizontalLimit - 24)
                let minimumHeight: CGFloat = isLandscape ? 180 : 220
                let maximumHeight = max(minimumHeight, canvasSize.height - 24)

                if isLandscape {
                    let requestedSide: CGFloat
                    if resizeWidth && resizeHeight {
                        requestedSide = start.width + max(
                            value.translation.width,
                            value.translation.height
                        )
                    } else if resizeWidth {
                        requestedSide = start.width + value.translation.width
                    } else {
                        requestedSide = start.height + value.translation.height
                    }

                    let maximumSide = max(180, min(maximumWidth, maximumHeight))
                    let side = min(maximumSide, max(180, requestedSide))
                    panelSize = CGSize(width: side, height: side)
                    panelCenter = boundedPanelCenter(
                        panelCenter,
                        panelSize: panelSize,
                        canvasSize: canvasSize
                    )
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
                panelCenter = boundedPanelCenter(
                    panelCenter,
                    panelSize: panelSize,
                    canvasSize: canvasSize
                )
            }
            .onEnded { _ in
                resizeStartSize = nil
            }
    }

    var textScrollGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !recorder.isProcessing else { return }

                let start = textDragStartOffset ?? scrollOffset
                textDragStartOffset = start
                scrollOffset = min(
                    maxScrollOffset,
                    max(0, start - value.translation.height)
                )
            }
            .onEnded { _ in
                textDragStartOffset = nil
            }
    }
}

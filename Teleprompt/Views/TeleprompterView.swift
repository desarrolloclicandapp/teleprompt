import SwiftUI

struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    let script: Script
    @StateObject private var voice = VoiceTracker()
    @State private var isPlaying = false
    @State private var speed: Double = 36
    @State private var fontSize: Double = 42
    @State private var mirrorHorizontal = false
    @State private var mirrorVertical = false
    @State private var countdown = 0
    @State private var showControls = true
    @State private var showRecording = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Text(script.text)
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 260)
                        .padding(.bottom, 520)
                        .scaleEffect(x: mirrorHorizontal ? -1 : 1, y: mirrorVertical ? -1 : 1)
                        .id("script")
                }
                .overlay(alignment: .center) {
                    Rectangle().fill(.mint.opacity(0.45)).frame(height: 2).allowsHitTesting(false)
                }
                .onChange(of: isPlaying) { _, playing in
                    guard playing else { return }
                    withAnimation(.linear(duration: max(1, 900 / speed)).repeatForever(autoreverses: false)) {
                        proxy.scrollTo("script", anchor: .bottom)
                    }
                }
            }

            if countdown > 0 {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.mint)
            }

            if showControls {
                VStack {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                        Spacer()
                        Text(script.title).font(.headline).lineLimit(1)
                        Spacer()
                        Button { showControls = false } label: { Image(systemName: "eye.slash") }
                    }
                    .padding()
                    .buttonStyle(.bordered)
                    Spacer()
                    controls
                }
                .foregroundStyle(.white)
            }
        }
        .statusBarHidden(!showControls)
        .onTapGesture { showControls.toggle() }
        .fullScreenCover(isPresented: $showRecording) { RecordingView(script: script) }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Velocidad", systemImage: "speedometer")
                Slider(value: $speed, in: 5...140)
                Text("\(Int(speed))")
                    .monospacedDigit()
                    .frame(width: 34)
            }
            HStack {
                Label("Texto", systemImage: "textformat.size")
                Slider(value: $fontSize, in: 20...100)
                Text("\(Int(fontSize))")
                    .monospacedDigit()
                    .frame(width: 34)
            }
            HStack(spacing: 16) {
                Button { mirrorHorizontal.toggle() } label: { Label("H", systemImage: "arrow.left.and.right") }
                Button { mirrorVertical.toggle() } label: { Label("V", systemImage: "arrow.up.and.down") }
                Button {
                    if voice.isListening { voice.stop() } else { Task { await voice.start() } }
                } label: {
                    Image(systemName: voice.isListening ? "waveform.circle.fill" : "waveform.circle")
                        .foregroundStyle(voice.isListening ? .mint : .white)
                }
                Button { showRecording = true } label: { Image(systemName: "video") }
                Spacer()
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
            }
            if voice.isListening {
                Text(voice.recognizedText.isEmpty ? "Escuchando…" : voice.recognizedText)
                    .font(.caption)
                    .foregroundStyle(.mint)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.black.opacity(0.82))
    }
}

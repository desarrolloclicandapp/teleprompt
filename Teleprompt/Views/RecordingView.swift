import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = CameraRecorder()
    let script: Script

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: recorder.session).ignoresSafeArea()
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title) }
                    Spacer()
                    Text(script.title).font(.headline)
                    Spacer()
                    Circle().fill(recorder.isRecording ? .red : .white.opacity(0.3)).frame(width: 14, height: 14)
                }
                .padding()
                Spacer()
                if let message = recorder.authorizationMessage {
                    Text(message).padding().background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                }
                Button { recorder.toggleRecording() } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(recorder.isRecording ? .red : .white)
                }
                .padding(.bottom, 24)
            }
            .foregroundStyle(.white)
        }
        .task { await recorder.prepare() }
    }
}


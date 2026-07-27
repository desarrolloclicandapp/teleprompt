import AVFoundation
import Foundation

@MainActor
final class CameraRecorder: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?
    @Published var authorizationMessage: String?

    func prepare() async {
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard camera && microphone else {
            authorizationMessage = "Activa cámara y micrófono en Ajustes para grabar."
            return
        }
        guard !session.isRunning, session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(videoInput) else { return }
        session.addInput(videoInput)

        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        Task { self.session.startRunning() }
    }

    func toggleRecording() {
        if isRecording {
            movieOutput.stopRecording()
        } else {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = directory.appendingPathComponent("Take-\(Int(Date().timeIntervalSince1970)).mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
            isRecording = true
        }
    }
}

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            if error == nil { self.lastRecordingURL = outputFileURL }
        }
    }
}

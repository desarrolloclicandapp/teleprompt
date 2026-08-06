import AVFoundation
import Foundation
import Photos
import UIKit

@MainActor
final class CameraRecorder: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var savedToPhotos = false
    @Published var authorizationMessage: String?

    private var recordingURLs: [URL] = []
    private var shouldFinalizeAfterStop = false
    private var isFinalizing = false

    func prepare() async {
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard camera && microphone else {
            authorizationMessage = "Activa la cámara y el micrófono en Ajustes para grabar."
            return
        }

        if !session.inputs.isEmpty {
            if !session.isRunning { session.startRunning() }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let videoInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(videoInput) else {
            authorizationMessage = "No se pudo abrir la cámara."
            return
        }
        session.addInput(videoInput)

        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        Task { self.session.startRunning() }
    }

    func toggleRecording(interfaceOrientation: UIInterfaceOrientation = .portrait) {
        if isRecording {
            stopRecording(finalizeSession: true)
        } else {
            startSession(interfaceOrientation: interfaceOrientation)
        }
    }

    func togglePauseResume(interfaceOrientation: UIInterfaceOrientation = .portrait) {
        guard isRecording else { return }
        if isPaused {
            isPaused = false
            startRecordingSegment(interfaceOrientation: interfaceOrientation)
        } else {
            isPaused = true
            stopRecording(finalizeSession: false)
        }
    }

    func stopRecordingSession() {
        guard isRecording else { return }
        isPaused = false
        stopRecording(finalizeSession: true)
    }

    private func startSession(interfaceOrientation: UIInterfaceOrientation) {
        isRecording = true
        isPaused = false
        shouldFinalizeAfterStop = false
        isFinalizing = false
        recordingURLs.removeAll()
        startRecordingSegment(interfaceOrientation: interfaceOrientation)
    }

    private func startRecordingSegment(interfaceOrientation: UIInterfaceOrientation) {
        guard isRecording, !isPaused else { return }
        if movieOutput.isRecording { return }

        if let connection = movieOutput.connection(with: .video) {
            let angle: CGFloat
            switch interfaceOrientation {
            case .landscapeLeft:
                angle = 90
            case .landscapeRight:
                angle = -90
            case .portraitUpsideDown:
                angle = 180
            default:
                angle = 0
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = tmpDir.appendingPathComponent("Take-\(Int(Date().timeIntervalSince1970)).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        savedToPhotos = false
    }

    private func stopRecording(finalizeSession: Bool) {
        shouldFinalizeAfterStop = shouldFinalizeAfterStop || finalizeSession
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            return
        }

        if finalizeSession {
            Task { @MainActor in
                await finalizeSessionIfNeeded()
            }
        }
    }

    private func finalizeSessionIfNeeded() async {
        guard !isFinalizing else { return }
        guard shouldFinalizeAfterStop else { return }

        isFinalizing = true
        shouldFinalizeAfterStop = false

        defer {
            isFinalizing = false
            isRecording = false
            isPaused = false
            clearTemporarySegments()
        }

        guard !recordingURLs.isEmpty else { return }

        let finalURL: URL? = if recordingURLs.count == 1 {
            recordingURLs.first
        } else {
            await mergeSegments()
        }

        if let finalURL {
            await saveToPhotoLibrary(finalURL)
            if finalURL.lastPathComponent.hasPrefix("Take-Merge-") {
                try? FileManager.default.removeItem(at: finalURL)
            }
        }
    }

    private func mergeSegments() async -> URL? {
        guard recordingURLs.count > 1 else { return recordingURLs.first }

        let composition = AVMutableComposition()
        guard
            let destinationVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else { return nil }

        let destinationAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        for url in recordingURLs {
            let asset = AVURLAsset(url: url)
            do {
                let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
                guard let sourceVideo = sourceVideoTracks.first else { continue }
                let duration = try await asset.load(.duration)

                try destinationVideo.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceVideo,
                    at: cursor
                )

                let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let sourceAudio = sourceAudioTracks.first,
                   let destinationAudio {
                    try destinationAudio.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: sourceAudio,
                        at: cursor
                    )
                }
            } catch {
                authorizationMessage = "No se pudieron unir los segmentos de video: \(error.localizedDescription)"
                return nil
            }

            cursor = cursor + duration
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let merged = tmpDir.appendingPathComponent("Take-Merge-\(Int(Date().timeIntervalSince1970)).mov")
        if FileManager.default.fileExists(atPath: merged.path) {
            try? FileManager.default.removeItem(at: merged)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            authorizationMessage = "No se pudo preparar la unión de segmentos."
            return nil
        }
        exporter.outputURL = merged
        exporter.outputFileType = .mov

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }

        guard exporter.status == .completed else {
            authorizationMessage = "No se pudo unir la grabación: \(exporter.error?.localizedDescription ?? "Error al exportar")"
            return nil
        }

        return merged
    }

    private func saveToPhotoLibrary(_ fileURL: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            authorizationMessage = "Permite guardar fotos y videos para enviar la grabación a Fotos."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            savedToPhotos = true
            authorizationMessage = nil
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            authorizationMessage = "No se pudo guardar el video en Fotos: \(error.localizedDescription)"
        }
    }

    private func clearTemporarySegments() {
        for url in recordingURLs {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURLs.removeAll()
    }

    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

extension CameraRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                authorizationMessage = "La grabación falló: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: outputFileURL)
                isRecording = false
                isPaused = false
                return
            }

            recordingURLs.append(outputFileURL)

            if shouldFinalizeAfterStop {
                await finalizeSessionIfNeeded()
            } else {
                isRecording = true
            }
        }
    }
}

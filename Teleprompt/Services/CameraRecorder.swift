@preconcurrency import AVFoundation
import Foundation
import Photos
import UIKit

@MainActor
final class CameraRecorder: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.viraltia.teleprompt.camera-session")

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isReady = false
    @Published private(set) var savedToPhotos = false
    @Published var authorizationMessage: String?

    private var recordingURLs: [URL] = []
    private var shouldFinalizeAfterStop = false
    private var isFinalizing = false
    private var isPreparing = false
    private var isStoppingSegment = false
    private var shouldResumeAfterStop = false
    private var pendingResumeOrientation: UIInterfaceOrientation = .portrait

    func prepare() async {
        if isReady {
            await startCaptureSessionIfNeeded()
            return
        }

        if isPreparing {
            for _ in 0..<200 where isPreparing {
                try? await Task.sleep(for: .milliseconds(25))
            }
            if isReady {
                await startCaptureSessionIfNeeded()
            }
            return
        }

        isPreparing = true
        defer { isPreparing = false }

        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard camera && microphone else {
            authorizationMessage = "Activa la cámara y el micrófono en Ajustes para grabar."
            return
        }

        if session.inputs.isEmpty {
            session.beginConfiguration()
            session.sessionPreset = .high
            defer { session.commitConfiguration() }

            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ),
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
        } else if !session.outputs.contains(where: { $0 === movieOutput }),
                  session.canAddOutput(movieOutput) {
            session.beginConfiguration()
            session.addOutput(movieOutput)
            session.commitConfiguration()
        }

        guard session.outputs.contains(where: { $0 === movieOutput }) else {
            authorizationMessage = "No se pudo preparar la salida de video."
            return
        }

        isReady = true
        authorizationMessage = nil
        await startCaptureSessionIfNeeded()
    }

    func toggleRecording(interfaceOrientation: UIInterfaceOrientation = .portrait) {
        if isRecording {
            stopRecording(finalizeSession: true)
        } else {
            startSession(interfaceOrientation: interfaceOrientation)
        }
    }

    func togglePauseResume(interfaceOrientation: UIInterfaceOrientation = .portrait) {
        guard isRecording, !isFinalizing else { return }
        pendingResumeOrientation = interfaceOrientation

        if isPaused {
            isPaused = false

            if isStoppingSegment || movieOutput.isRecording {
                shouldResumeAfterStop = true
            } else {
                startRecordingSegment(interfaceOrientation: interfaceOrientation)
            }
        } else {
            isPaused = true
            shouldResumeAfterStop = false
            stopRecording(finalizeSession: false)
        }
    }

    func stopRecordingSession() {
        guard isRecording else { return }
        isPaused = false
        shouldResumeAfterStop = false
        stopRecording(finalizeSession: true)
    }

    func stopRecordingSessionAndWait() async {
        guard isRecording else { return }
        isPaused = false
        shouldResumeAfterStop = false
        stopRecording(finalizeSession: true)

        for _ in 0..<300 {
            if !isRecording,
               !shouldFinalizeAfterStop,
               !isFinalizing,
               !isStoppingSegment {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func startSession(interfaceOrientation: UIInterfaceOrientation) {
        guard isReady else {
            authorizationMessage = "Espera a que la cámara termine de prepararse antes de grabar."
            return
        }

        isRecording = true
        isPaused = false
        shouldFinalizeAfterStop = false
        isFinalizing = false
        isStoppingSegment = false
        shouldResumeAfterStop = false
        pendingResumeOrientation = interfaceOrientation
        recordingURLs.removeAll()
        startRecordingSegment(interfaceOrientation: interfaceOrientation)
    }

    private func startRecordingSegment(interfaceOrientation: UIInterfaceOrientation) {
        guard isRecording, !isPaused, !isStoppingSegment, !isFinalizing else { return }
        guard !movieOutput.isRecording else { return }

        if let connection = movieOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            switch interfaceOrientation {
            case .landscapeLeft:
                connection.videoOrientation = .landscapeLeft
            case .landscapeRight:
                connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            default:
                connection.videoOrientation = .portrait
            }
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = tmpDir.appendingPathComponent("Take-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        savedToPhotos = false
    }

    private func stopRecording(finalizeSession: Bool) {
        shouldFinalizeAfterStop = shouldFinalizeAfterStop || finalizeSession
        if finalizeSession {
            shouldResumeAfterStop = false
        }

        if movieOutput.isRecording {
            isStoppingSegment = true
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
        guard !isFinalizing, shouldFinalizeAfterStop else { return }

        isFinalizing = true
        shouldFinalizeAfterStop = false
        shouldResumeAfterStop = false

        defer {
            isFinalizing = false
            isRecording = false
            isPaused = false
            isStoppingSegment = false
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
        guard let destinationVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return nil
        }

        let destinationAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        var appliedVideoTransform = false

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

                if !appliedVideoTransform {
                    destinationVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
                    appliedVideoTransform = true
                }

                let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
                if let sourceAudio = sourceAudioTracks.first,
                   let destinationAudio {
                    try destinationAudio.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: sourceAudio,
                        at: cursor
                    )
                }
                cursor = cursor + duration
            } catch {
                authorizationMessage = "No se pudieron unir los segmentos de video: \(error.localizedDescription)"
                return nil
            }
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let merged = tmpDir.appendingPathComponent("Take-Merge-\(UUID().uuidString).mov")

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
            exporter.exportAsynchronously {
                continuation.resume()
            }
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

    private func startCaptureSessionIfNeeded() async {
        let captureSession = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
                continuation.resume()
            }
        }
    }

    func stopSession() {
        let captureSession = session
        sessionQueue.async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
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
            isStoppingSegment = false

            if let error {
                authorizationMessage = "La grabación falló: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: outputFileURL)
                shouldResumeAfterStop = false
                isRecording = false
                isPaused = false
                return
            }

            recordingURLs.append(outputFileURL)

            if shouldFinalizeAfterStop {
                await finalizeSessionIfNeeded()
            } else if shouldResumeAfterStop {
                shouldResumeAfterStop = false
                startRecordingSegment(interfaceOrientation: pendingResumeOrientation)
            } else {
                isRecording = true
            }
        }
    }
}

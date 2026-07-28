import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        configure(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        configure(uiView)
    }

    private func configure(_ view: PreviewView) {
        view.previewLayer.videoGravity = .resizeAspect
        view.lockCameraOrientation()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        lockCameraOrientation()
    }

    /// The reader UI can rotate, but the camera feed must always remain in its
    /// native portrait presentation. Reapply this after layout because iOS can
    /// recreate or update the preview connection during an interface rotation.
    func lockCameraOrientation() {
        guard let connection = previewLayer.connection else { return }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        } else if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

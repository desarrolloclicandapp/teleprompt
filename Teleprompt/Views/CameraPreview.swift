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
        guard let connection = view.previewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.refreshVideoOrientation()
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    override func layoutSubviews() {
        super.layoutSubviews()
        updateVideoOrientation()

        // During a rotation the view can lay out before its window scene has
        // received the new interface orientation. Reapply once after UIKit
        // finishes the transition so the preview cannot remain sideways.
        DispatchQueue.main.async { [weak self] in
            self?.updateVideoOrientation()
        }
    }

    func updateVideoOrientation() {
        guard let connection = previewLayer.connection,
              let device = previewLayer.session?.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else { return }

        if #available(iOS 17.0, *) {
            if rotationCoordinator?.device !== device || rotationCoordinator?.previewLayer !== previewLayer {
                rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: device,
                    previewLayer: previewLayer
                )
            }
            let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview ?? 0
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    func refreshVideoOrientation() {
        updateVideoOrientation()
        for delay in [0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updateVideoOrientation()
            }
        }
    }
}

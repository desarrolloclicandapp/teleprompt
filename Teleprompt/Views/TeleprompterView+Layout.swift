import SwiftUI
import UIKit

extension TeleprompterView {
    func updatePanelLayout(
        for size: CGSize,
        safeAreaInsets: EdgeInsets,
        forceReset: Bool = false
    ) {
        guard size.width > 1, size.height > 1 else { return }

        let landscape = size.width > size.height
        let orientationChanged = landscape != layoutIsLandscape
        let previousCameraSide = cameraSideIsTrailing

        if landscape {
            cameraSideIsTrailing = cameraSide(
                for: currentInterfaceOrientation,
                safeAreaInsets: safeAreaInsets
            )
        }

        let sideChanged = landscape && previousCameraSide != cameraSideIsTrailing
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
            panelCenter = boundedPanelCenter(
                panelCenter,
                panelSize: panelSize,
                canvasSize: size
            )
        }
    }

    func defaultPanelSize(for size: CGSize, isLandscape: Bool) -> CGSize {
        if isLandscape {
            let cameraRegionWidth = showCamera ? size.width * 0.5 : size.width
            let side = min(
                max(180, cameraRegionWidth - 24),
                max(180, min(size.height * 0.82, cameraRegionWidth - 24))
            )
            return CGSize(width: side, height: side)
        }

        return CGSize(
            width: min(max(220, size.width - 24), 420),
            height: min(max(240, size.height * 0.42), max(240, size.height - 24))
        )
    }

    func limitedPanelSize(
        _ size: CGSize,
        for canvas: CGSize,
        isLandscape: Bool
    ) -> CGSize {
        let horizontalLimit = isLandscape && showCamera
            ? canvas.width * 0.5
            : canvas.width
        let minimumHeight: CGFloat = isLandscape ? 180 : 220

        if isLandscape {
            let maximumSide = max(180, min(horizontalLimit - 24, canvas.height - 24))
            let side = min(maximumSide, max(180, min(size.width, size.height)))
            return CGSize(width: side, height: side)
        }

        return CGSize(
            width: min(max(180, horizontalLimit - 24), max(180, size.width)),
            height: min(
                max(minimumHeight, canvas.height - 24),
                max(minimumHeight, size.height)
            )
        )
    }

    func cameraSide(
        for orientation: UIInterfaceOrientation,
        safeAreaInsets: EdgeInsets
    ) -> Bool {
        switch orientation {
        case .landscapeLeft:
            return true
        case .landscapeRight:
            return false
        default:
            return safeAreaInsets.trailing >= safeAreaInsets.leading
        }
    }

    func defaultPanelCenter(
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

    func boundedPanelCenter(
        _ center: CGPoint,
        panelSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let panelHalfWidth = panelSize.width / 2
        let minimumX: CGFloat
        let maximumX: CGFloat

        if canvasSize.width > canvasSize.height && showCamera {
            let cameraRegionWidth = canvasSize.width * 0.5
            if cameraSideIsTrailing {
                minimumX = canvasSize.width - cameraRegionWidth + panelHalfWidth + 8
                maximumX = max(minimumX, canvasSize.width - panelHalfWidth - 8)
            } else {
                minimumX = panelHalfWidth + 8
                maximumX = max(minimumX, cameraRegionWidth - panelHalfWidth - 8)
            }
        } else {
            minimumX = panelHalfWidth + 8
            maximumX = max(minimumX, canvasSize.width - panelHalfWidth - 8)
        }

        let minimumY = panelSize.height / 2 + 8
        let maximumY = max(minimumY, canvasSize.height - panelSize.height / 2 - 8)

        return CGPoint(
            x: min(max(center.x, minimumX), maximumX),
            y: min(max(center.y, minimumY), maximumY)
        )
    }
}

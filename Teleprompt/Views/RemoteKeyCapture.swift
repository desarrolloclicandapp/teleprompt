import SwiftUI
import UIKit

struct RemoteKeyCapture: UIViewRepresentable {
    let onAction: (RemoteAction) -> Void

    func makeUIView(context: Context) -> RemoteKeyView {
        let view = RemoteKeyView()
        view.onAction = onAction
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: RemoteKeyView, context: Context) { uiView.onAction = onAction }
}

enum RemoteAction {
    case playPause
    case next
    case previous
    case reset
    case toggleRecording
    case toggleRecordingPause
    case increaseSpeed
    case decreaseSpeed
    case joystick(x: Double, y: Double)
}

final class RemoteKeyView: UIView {
    var onAction: ((RemoteAction) -> Void)?
    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let code = press.key?.keyCode else { continue }
            switch code {
            case .keyboardSpacebar: onAction?(.playPause)
            case .keyboardRightArrow, .keyboardPageDown: onAction?(.next)
            case .keyboardLeftArrow, .keyboardPageUp: onAction?(.previous)
            case .keyboardHome: onAction?(.reset)
            case .keyboardUpArrow: onAction?(.increaseSpeed)
            case .keyboardDownArrow: onAction?(.decreaseSpeed)
            default: break
            }
        }
    }
}

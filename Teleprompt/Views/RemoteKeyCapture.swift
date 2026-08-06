import SwiftUI
import UIKit

struct RemoteKeyCapture: UIViewRepresentable {
    let onAction: (RemoteAction) -> Void

    func makeUIView(context: Context) -> RemoteKeyView {
        let view = RemoteKeyView()
        view.onAction = onAction
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: RemoteKeyView, context: Context) {
        uiView.onAction = onAction
        if !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }
}

enum RemoteAction {
    case playPause
    case toggleControls
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handledAny = false

        for press in presses {
            guard let code = press.key?.keyCode else { continue }

            let action: RemoteAction?
            switch code {
            // Direct A/B/X/Y mapping when the pad exposes itself as a BLE keyboard.
            case .keyboardA:
                action = .playPause
            case .keyboardB:
                action = .toggleControls
            case .keyboardX:
                action = .toggleRecordingPause
            case .keyboardY:
                action = .toggleRecording

            // Common teleprompter and presentation-remote fallbacks.
            case .keyboardSpacebar:
                action = .playPause
            case .keyboardPageDown:
                action = .toggleControls
            case .keyboardPageUp:
                action = .toggleRecordingPause
            case .keyboardHome:
                action = .reset

            // Digital joystick fallback for remotes that send arrow keys.
            case .keyboardRightArrow:
                action = .increaseSpeed
            case .keyboardLeftArrow:
                action = .decreaseSpeed
            case .keyboardUpArrow:
                action = .previous
            case .keyboardDownArrow:
                action = .next
            default:
                action = nil
            }

            if let action {
                handledAny = true
                onAction?(action)
            }
        }

        if !handledAny {
            super.pressesBegan(presses, with: event)
        }
    }
}

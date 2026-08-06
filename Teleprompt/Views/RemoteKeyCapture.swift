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
    private var activeKeyCodes: Set<UIKeyboardHIDUsage> = []

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            activeKeyCodes.removeAll()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []

        for press in presses {
            guard let code = press.key?.keyCode,
                  let action = action(for: code) else {
                unhandled.insert(press)
                continue
            }

            // A held key can repeat rapidly. Toggle actions must execute once
            // per physical press, not once per keyboard-repeat event.
            guard activeKeyCodes.insert(code).inserted else { continue }
            onAction?(action)
        }

        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseKeyCodes(in: presses)
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseKeyCodes(in: presses)
        super.pressesCancelled(presses, with: event)
    }

    private func releaseKeyCodes(in presses: Set<UIPress>) {
        for press in presses {
            if let code = press.key?.keyCode {
                activeKeyCodes.remove(code)
            }
        }
    }

    private func action(for code: UIKeyboardHIDUsage) -> RemoteAction? {
        switch code {
        // Direct A/B/X/Y mapping when the pad exposes itself as a BLE keyboard.
        case .keyboardA:
            return .playPause
        case .keyboardB:
            return .toggleControls
        case .keyboardX:
            return .toggleRecordingPause
        case .keyboardY:
            return .toggleRecording

        // Common teleprompter and presentation-remote fallbacks.
        case .keyboardSpacebar:
            return .playPause
        case .keyboardPageDown:
            return .toggleControls
        case .keyboardPageUp:
            return .toggleRecordingPause
        case .keyboardHome:
            return .reset

        // Digital joystick fallback for remotes that send arrow keys.
        case .keyboardRightArrow:
            return .increaseSpeed
        case .keyboardLeftArrow:
            return .decreaseSpeed
        case .keyboardUpArrow:
            return .previous
        case .keyboardDownArrow:
            return .next
        default:
            return nil
        }
    }
}

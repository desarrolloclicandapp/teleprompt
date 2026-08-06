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
            emitKeyboardJoystick()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []

        for press in presses {
            guard let code = press.key?.keyCode else {
                unhandled.insert(press)
                continue
            }

            if isJoystickKey(code) {
                guard activeKeyCodes.insert(code).inserted else { continue }
                emitKeyboardJoystick()
                continue
            }

            guard let action = action(for: code) else {
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
        let releasedJoystick = releaseKeyCodes(in: presses)
        if releasedJoystick {
            emitKeyboardJoystick()
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let releasedJoystick = releaseKeyCodes(in: presses)
        if releasedJoystick {
            emitKeyboardJoystick()
        }
        super.pressesCancelled(presses, with: event)
    }

    @discardableResult
    private func releaseKeyCodes(in presses: Set<UIPress>) -> Bool {
        var releasedJoystick = false
        for press in presses {
            if let code = press.key?.keyCode {
                activeKeyCodes.remove(code)
                releasedJoystick = releasedJoystick || isJoystickKey(code)
            }
        }
        return releasedJoystick
    }

    private func isJoystickKey(_ code: UIKeyboardHIDUsage) -> Bool {
        switch code {
        case .keyboardLeftArrow,
             .keyboardRightArrow,
             .keyboardUpArrow,
             .keyboardDownArrow:
            return true
        default:
            return false
        }
    }

    private func emitKeyboardJoystick() {
        let left = activeKeyCodes.contains(.keyboardLeftArrow)
        let right = activeKeyCodes.contains(.keyboardRightArrow)
        let up = activeKeyCodes.contains(.keyboardUpArrow)
        let down = activeKeyCodes.contains(.keyboardDownArrow)

        let x: Double
        if left == right {
            x = 0
        } else {
            x = right ? 1 : -1
        }

        let y: Double
        if up == down {
            y = 0
        } else {
            // Match GameController: pushing up produces a positive Y value.
            y = up ? 1 : -1
        }

        onAction?(.joystick(x: x, y: y))
    }

    private func action(for code: UIKeyboardHIDUsage) -> RemoteAction? {
        switch code {
        // Literal keyboard/gamepad mode used by some generic controllers.
        case .keyboardA:
            return .playPause
        case .keyboardB:
            return .toggleControls
        case .keyboardX:
            return .toggleRecordingPause

        // TeleprompterPAD/RemotePAD iOS preset:
        // physical A -> fast forward -> R/U or Page Down
        // physical B -> rewind -> F/H or Page Up
        // physical X -> play/pause -> Y or Space
        // physical Y -> go to top -> J or Home
        case .keyboardR, .keyboardU, .keyboardPageDown:
            return .playPause
        case .keyboardF, .keyboardH, .keyboardPageUp:
            return .toggleControls
        case .keyboardY, .keyboardSpacebar:
            return .toggleRecordingPause
        case .keyboardJ, .keyboardHome:
            return .toggleRecording

        default:
            return nil
        }
    }
}

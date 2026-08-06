import GameController
import SwiftUI
import UIKit

struct RemoteKeyCapture: UIViewRepresentable {
    let onAction: (RemoteAction) -> Void

    func makeUIView(context: Context) -> RemoteKeyView {
        let view = RemoteKeyView()
        view.onAction = onAction
        DispatchQueue.main.async {
            view.activateCapture()
        }
        return view
    }

    func updateUIView(_ uiView: RemoteKeyView, context: Context) {
        uiView.onAction = onAction
        uiView.activateCapture()
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

    private var activeUIKitKeyCodes: Set<UIKeyboardHIDUsage> = []
    private var activeGameControllerKeyCodes: Set<GCKeyCode> = []
    private var keyboardConnectObserver: NSObjectProtocol?
    private var keyboardDisconnectObserver: NSObjectProtocol?
    private var boundKeyboardInput: GCKeyboardInput?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil else {
            stopKeyboardCapture()
            clearPressedKeys()
            return
        }

        activateCapture()
    }

    deinit {
        if let keyboardConnectObserver {
            NotificationCenter.default.removeObserver(keyboardConnectObserver)
        }
        if let keyboardDisconnectObserver {
            NotificationCenter.default.removeObserver(keyboardDisconnectObserver)
        }
        boundKeyboardInput?.keyChangedHandler = nil
    }

    func activateCapture() {
        guard window != nil else { return }

        if !isFirstResponder {
            becomeFirstResponder()
        }

        startKeyboardCaptureIfNeeded()
        bindCoalescedKeyboard()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []

        for press in presses {
            guard let code = press.key?.keyCode else {
                unhandled.insert(press)
                continue
            }

            if isJoystickKey(code) {
                guard activeUIKitKeyCodes.insert(code).inserted else { continue }
                emitKeyboardJoystick()
                continue
            }

            guard let action = action(for: code) else {
                unhandled.insert(press)
                continue
            }

            guard activeUIKitKeyCodes.insert(code).inserted else { continue }
            onAction?(action)
        }

        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let releasedJoystick = releaseUIKitKeyCodes(in: presses)
        if releasedJoystick {
            emitKeyboardJoystick()
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let releasedJoystick = releaseUIKitKeyCodes(in: presses)
        if releasedJoystick {
            emitKeyboardJoystick()
        }
        super.pressesCancelled(presses, with: event)
    }

    private func startKeyboardCaptureIfNeeded() {
        guard keyboardConnectObserver == nil, keyboardDisconnectObserver == nil else { return }

        keyboardConnectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let keyboard = notification.object as? GCKeyboard else { return }
            self?.bindKeyboard(keyboard)
        }

        keyboardDisconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.unbindKeyboard()
            self?.bindCoalescedKeyboard()
        }
    }

    private func stopKeyboardCapture() {
        if let keyboardConnectObserver {
            NotificationCenter.default.removeObserver(keyboardConnectObserver)
            self.keyboardConnectObserver = nil
        }

        if let keyboardDisconnectObserver {
            NotificationCenter.default.removeObserver(keyboardDisconnectObserver)
            self.keyboardDisconnectObserver = nil
        }

        unbindKeyboard()
    }

    private func bindCoalescedKeyboard() {
        guard let keyboard = GCKeyboard.coalesced else { return }
        bindKeyboard(keyboard)
    }

    private func bindKeyboard(_ keyboard: GCKeyboard) {
        guard let input = keyboard.keyboardInput else { return }
        guard boundKeyboardInput !== input else { return }

        unbindKeyboard()
        boundKeyboardInput = input
        input.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            DispatchQueue.main.async {
                self?.handleGameControllerKey(keyCode, pressed: pressed)
            }
        }
    }

    private func unbindKeyboard() {
        boundKeyboardInput?.keyChangedHandler = nil
        boundKeyboardInput = nil
        activeGameControllerKeyCodes.removeAll()
        emitKeyboardJoystick()
    }

    private func handleGameControllerKey(_ code: GCKeyCode, pressed: Bool) {
        if isJoystickKey(code) {
            if pressed {
                activeGameControllerKeyCodes.insert(code)
            } else {
                activeGameControllerKeyCodes.remove(code)
            }
            emitKeyboardJoystick()
            return
        }

        if pressed {
            guard activeGameControllerKeyCodes.insert(code).inserted else { return }
            if let action = action(for: code) {
                onAction?(action)
            } else {
                logUnhandledGameControllerKey(code)
            }
        } else {
            activeGameControllerKeyCodes.remove(code)
        }
    }

    @discardableResult
    private func releaseUIKitKeyCodes(in presses: Set<UIPress>) -> Bool {
        var releasedJoystick = false

        for press in presses {
            if let code = press.key?.keyCode {
                activeUIKitKeyCodes.remove(code)
                releasedJoystick = releasedJoystick || isJoystickKey(code)
            }
        }

        return releasedJoystick
    }

    private func clearPressedKeys() {
        activeUIKitKeyCodes.removeAll()
        activeGameControllerKeyCodes.removeAll()
        emitKeyboardJoystick()
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

    private func isJoystickKey(_ code: GCKeyCode) -> Bool {
        switch code {
        case .leftArrow, .rightArrow, .upArrow, .downArrow:
            return true
        default:
            return false
        }
    }

    private func emitKeyboardJoystick() {
        let left = activeUIKitKeyCodes.contains(.keyboardLeftArrow)
            || activeGameControllerKeyCodes.contains(.leftArrow)
        let right = activeUIKitKeyCodes.contains(.keyboardRightArrow)
            || activeGameControllerKeyCodes.contains(.rightArrow)
        let up = activeUIKitKeyCodes.contains(.keyboardUpArrow)
            || activeGameControllerKeyCodes.contains(.upArrow)
        let down = activeUIKitKeyCodes.contains(.keyboardDownArrow)
            || activeGameControllerKeyCodes.contains(.downArrow)

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
            y = up ? 1 : -1
        }

        onAction?(.joystick(x: x, y: y))
    }

    private func action(for code: UIKeyboardHIDUsage) -> RemoteAction? {
        switch code {
        // Literal game-controller keyboard fallbacks.
        case .keyboardA, .keyboardReturnOrEnter:
            return .playPause
        case .keyboardB, .keyboardEscape:
            return .toggleControls
        case .keyboardX:
            return .toggleRecordingPause

        // Official TeleprompterPAD iOS mapping:
        // physical A -> R/U or Page Down (fast forward)
        // physical B -> F/H or Page Up (rewind)
        // physical X -> Y or Space (play/pause)
        // physical Y -> J or Home (go to top)
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

    private func action(for code: GCKeyCode) -> RemoteAction? {
        switch code {
        // Literal game-controller keyboard fallbacks.
        case .keyA, .returnOrEnter:
            return .playPause
        case .keyB, .escape:
            return .toggleControls
        case .keyX:
            return .toggleRecordingPause

        // Official TeleprompterPAD iOS keyboard mapping.
        case .keyR, .keyU, .pageDown:
            return .playPause
        case .keyF, .keyH, .pageUp:
            return .toggleControls
        case .keyY, .spacebar:
            return .toggleRecordingPause
        case .keyJ, .home:
            return .toggleRecording

        default:
            return nil
        }
    }

    private func logUnhandledGameControllerKey(_ code: GCKeyCode) {
#if DEBUG
        print("[RemotePAD] Unhandled GCKeyboard key code: \(code.rawValue)")
#endif
    }
}

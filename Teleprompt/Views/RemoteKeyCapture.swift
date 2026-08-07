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

    // UIKit and GCKeyboard report the same physical HID event a few
    // milliseconds apart on this RemotePAD. Keep a tiny cross-channel
    // dedupe window for the measured joystick pulses while still allowing
    // the next hardware repeat (~50 ms later) through.
    private var lastMeasuredJoystickRaw: Int?
    private var lastMeasuredJoystickAt = Date.distantPast

    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { false }

    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []

        // Secondary TeleprompterPAD keyboard-mode compatibility mappings.
        commands += letterCommands("r", action: #selector(handlePlayPauseCommand(_:)))
        commands += letterCommands("u", action: #selector(handlePlayPauseCommand(_:)))
        commands += letterCommands("a", action: #selector(handlePlayPauseCommand(_:)))

        commands += letterCommands("f", action: #selector(handleToggleControlsCommand(_:)))
        commands += letterCommands("h", action: #selector(handleToggleControlsCommand(_:)))
        commands += letterCommands("b", action: #selector(handleToggleControlsCommand(_:)))

        commands += letterCommands("y", action: #selector(handleRecordingPauseCommand(_:)))
        commands += letterCommands("x", action: #selector(handleRecordingPauseCommand(_:)))
        commands += letterCommands("j", action: #selector(handleRecordingCommand(_:)))

        // Standard arrow-key fallback. The measured iPhone GAME-mode joystick
        // uses different HID usages, handled below by rawValue.
        commands.append(
            priorityCommand(
                UIKeyCommand.inputLeftArrow,
                action: #selector(handleDecreaseSpeedCommand(_:))
            )
        )
        commands.append(
            priorityCommand(
                UIKeyCommand.inputRightArrow,
                action: #selector(handleIncreaseSpeedCommand(_:))
            )
        )
        commands.append(
            priorityCommand(
                UIKeyCommand.inputUpArrow,
                action: #selector(handleMoveTextUpCommand(_:))
            )
        )
        commands.append(
            priorityCommand(
                UIKeyCommand.inputDownArrow,
                action: #selector(handleMoveTextDownCommand(_:))
            )
        )

        return commands
    }

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
            guard let key = press.key else {
                unhandled.insert(press)
                continue
            }

            let raw = Int(key.keyCode.rawValue)
            RemoteInputDiagnostics.shared.log(
                "KEY-RAW",
                "chars=\(key.charactersIgnoringModifiers.debugDescription) hid=\(raw)"
            )

            // Measured iPhone GAME-mode joystick. These are digital HID pulses,
            // not an analog GCController thumbstick. Handle the distinctive
            // entry/repeat usages directly.
            if emitMeasuredJoystick(raw: raw) {
                continue
            }

            let code = key.keyCode
            if isStandardJoystickKey(code) {
                guard activeUIKitKeyCodes.insert(code).inserted else { continue }
                emitStandardKeyboardJoystick()
                continue
            }

            guard let action = action(for: key) else {
                unhandled.insert(press)
                continue
            }

            // A/B/X/Y are discrete toggles. Run once until key-up even if the
            // RemotePAD generates keyboard auto-repeat while held.
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
            emitStandardKeyboardJoystick()
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let releasedJoystick = releaseUIKitKeyCodes(in: presses)
        if releasedJoystick {
            emitStandardKeyboardJoystick()
        }
        super.pressesCancelled(presses, with: event)
    }

    private func letterCommands(_ input: String, action: Selector) -> [UIKeyCommand] {
        [
            priorityCommand(input, action: action),
            priorityCommand(input, modifiers: [.shift], action: action)
        ]
    }

    private func priorityCommand(
        _ input: String,
        modifiers: UIKeyModifierFlags = [],
        action: Selector
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: modifiers,
            action: action
        )
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func handlePlayPauseCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "playPause input=\(command.input ?? "nil")")
        onAction?(.playPause)
    }

    @objc private func handleToggleControlsCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "toggleControls input=\(command.input ?? "nil")")
        onAction?(.toggleControls)
    }

    @objc private func handleRecordingPauseCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "recordingPause input=\(command.input ?? "nil")")
        onAction?(.toggleRecordingPause)
    }

    @objc private func handleRecordingCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "recording input=\(command.input ?? "nil")")
        onAction?(.toggleRecording)
    }

    @objc private func handleDecreaseSpeedCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "left/decreaseSpeed")
        onAction?(.decreaseSpeed)
    }

    @objc private func handleIncreaseSpeedCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "right/increaseSpeed")
        onAction?(.increaseSpeed)
    }

    @objc private func handleMoveTextUpCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "up/moveTextUp")
        onAction?(.next)
    }

    @objc private func handleMoveTextDownCommand(_ command: UIKeyCommand) {
        RemoteInputDiagnostics.shared.log("KEY-CMD", "down/moveTextDown")
        onAction?(.previous)
    }

    private func startKeyboardCaptureIfNeeded() {
        guard keyboardConnectObserver == nil, keyboardDisconnectObserver == nil else { return }

        keyboardConnectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let keyboard = notification.object as? GCKeyboard else { return }
            RemoteInputDiagnostics.shared.log("GC-KEYBOARD", "connected")
            self?.bindKeyboard(keyboard)
        }

        keyboardDisconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            RemoteInputDiagnostics.shared.log("GC-KEYBOARD", "disconnected")
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
        emitStandardKeyboardJoystick()
    }

    private func handleGameControllerKey(_ code: GCKeyCode, pressed: Bool) {
        let raw = Int(code.rawValue)
        RemoteInputDiagnostics.shared.log(
            "GC-KEY-RAW",
            "code=\(raw) pressed=\(pressed)"
        )

        if pressed, emitMeasuredJoystick(raw: raw) {
            return
        }

        if isStandardJoystickKey(code) {
            if pressed {
                activeGameControllerKeyCodes.insert(code)
            } else {
                activeGameControllerKeyCodes.remove(code)
            }
            emitStandardKeyboardJoystick()
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

    // MARK: - Measured TeleprompterPAD iPhone GAME-mode contract

    private func measuredButtonAction(raw: Int) -> RemoteAction? {
        switch raw {
        // Native iPhone log, physical test order A / B / X / Y.
        case 42: // Backspace
            return .playPause
        case 41: // Escape
            return .toggleControls
        case 44: // Space
            return .toggleRecordingPause
        case 45: // Hyphen/apostrophe depending keyboard layout
            return .toggleRecording

        // Windows GAME-mode fallback measured on the same RemotePAD.
        case 30: // 1
            return .playPause
        case 31: // 2
            return .toggleControls
        case 33: // 4
            return .toggleRecordingPause
        case 32: // 3
            return .toggleRecording
        default:
            return nil
        }
    }

    private func measuredJoystickAction(raw: Int) -> RemoteAction? {
        switch raw {
        // Native iPhone GAME-mode positions, adjusted from the physical test:
        // Left = speed up, Right = move text up, Up = speed down, Down = move text down.
        case 115, 109:
            return .increaseSpeed
        case 88, 96:
            return .next
        case 62, 107:
            return .decreaseSpeed
        case 143, 146:
            return .previous
        default:
            return nil
        }
    }

    @discardableResult
    private func emitMeasuredJoystick(raw: Int) -> Bool {
        guard let action = measuredJoystickAction(raw: raw) else { return false }

        let now = Date()
        if lastMeasuredJoystickRaw == raw,
           now.timeIntervalSince(lastMeasuredJoystickAt) < 0.025 {
            return true
        }

        lastMeasuredJoystickRaw = raw
        lastMeasuredJoystickAt = now
        RemoteInputDiagnostics.shared.log("IOS-HID", "raw=\(raw) -> \(action.diagnosticsName)")
        onAction?(action)
        return true
    }

    // MARK: - Standard keyboard fallback

    @discardableResult
    private func releaseUIKitKeyCodes(in presses: Set<UIPress>) -> Bool {
        var releasedJoystick = false

        for press in presses {
            if let code = press.key?.keyCode {
                activeUIKitKeyCodes.remove(code)
                releasedJoystick = releasedJoystick || isStandardJoystickKey(code)
            }
        }

        return releasedJoystick
    }

    private func clearPressedKeys() {
        activeUIKitKeyCodes.removeAll()
        activeGameControllerKeyCodes.removeAll()
        emitStandardKeyboardJoystick()
    }

    private func isStandardJoystickKey(_ code: UIKeyboardHIDUsage) -> Bool {
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

    private func isStandardJoystickKey(_ code: GCKeyCode) -> Bool {
        switch code {
        case .leftArrow, .rightArrow, .upArrow, .downArrow:
            return true
        default:
            return false
        }
    }

    private func emitStandardKeyboardJoystick() {
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

    private func action(for key: UIKey) -> RemoteAction? {
        let raw = Int(key.keyCode.rawValue)
        if let measured = measuredButtonAction(raw: raw) {
            return measured
        }

        let characters = key.charactersIgnoringModifiers.lowercased()

        // Secondary compatibility mappings for other modes/models.
        switch characters {
        case "r", "u", "a":
            return .playPause
        case "f", "h", "b":
            return .toggleControls
        case "y", "x", " ":
            return .toggleRecordingPause
        case "j":
            return .toggleRecording
        default:
            break
        }

        switch key.keyCode {
        case .keyboardReturnOrEnter, .keyboardPageDown:
            return .playPause
        case .keyboardEscape, .keyboardPageUp:
            return .toggleControls
        case .keyboardHome:
            return .toggleRecording
        default:
            return nil
        }
    }

    private func action(for code: GCKeyCode) -> RemoteAction? {
        let raw = Int(code.rawValue)
        if let measured = measuredButtonAction(raw: raw) {
            return measured
        }

        // Secondary compatibility mappings.
        switch code {
        case .keyR, .keyU, .keyA, .returnOrEnter, .pageDown:
            return .playPause
        case .keyF, .keyH, .keyB, .escape, .pageUp:
            return .toggleControls
        case .keyY, .keyX, .spacebar:
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
